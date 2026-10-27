import Foundation

/// Context-window measurement for the chat feed.
///
/// Providers silently truncate once the prompt exceeds the model window, so the
/// app must measure before sending. This is a heuristic (chars/4 for Latin,
/// one token per CJK/emoji scalar) — deliberately conservative and cheap: it
/// runs on every send and never calls a tokenizer API. Real `usage.promptTokens`
/// from the provider, when present, is more accurate and can override it.
struct ContextUsage: Equatable {
    let usedTokens: Int
    let limitTokens: Int

    var ratio: Double {
        guard limitTokens > 0 else { return 0 }
        return min(1, Double(usedTokens) / Double(limitTokens))
    }

    var percent: Int { Int((ratio * 100).rounded()) }

    var remainingTokens: Int { max(0, limitTokens - usedTokens) }
}

enum ContextUsageLogic {
    /// Recommended compaction trigger (plan: auto-compact at 90%).
    static let compactThreshold = 0.9

    /// Image parts are billed by the provider as a fixed tile budget; counting
    /// them as text would understate the prompt. 1200 is a conservative
    /// mid-size estimate for the vision models myCoder supports.
    static let tokensPerImage = 1_200

    /// Per-message role/format overhead (chat template tokens).
    static let tokensPerMessage = 4

    static func estimateTokens(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        var wide = 0
        var narrow = 0
        for scalar in text.unicodeScalars {
            // CJK, Hangul, Hiragana/Katakana and emoji: ~1 token each.
            if scalar.value >= 0x2E80 { wide += 1 } else { narrow += 1 }
        }
        return wide + (narrow + 3) / 4
    }

    static func tokens(for message: Message) -> Int {
        var total = tokensPerMessage
        total += estimateTokens(message.content)
        total += estimateTokens(message.reasoning)
        for part in message.parts {
            switch part {
            case .text(let t):
                total += estimateTokens(t)
            case .reasoning(let r):
                total += estimateTokens(r)
            case .toolCall(let name, let args, let result, _):
                total += estimateTokens(name) + estimateTokens(args)
                if let result { total += estimateTokens(result) }
            case .image:
                total += tokensPerImage
            case .compiledContext(let text):
                total += estimateTokens(text)
            case .stepStart, .stepFinish, .routeInfo:
                break
            }
        }
        return total
    }

    static func usedTokens(messages: [Message]) -> Int {
        messages.reduce(0) { $0 + tokens(for: $1) }
    }

    static func usage(messages: [Message], limitTokens: Int) -> ContextUsage {
        ContextUsage(usedTokens: usedTokens(messages: messages), limitTokens: limitTokens)
    }

    static func shouldCompact(_ usage: ContextUsage, threshold: Double = compactThreshold) -> Bool {
        usage.limitTokens > 0 && usage.ratio >= threshold
    }

    static func badgeText(_ usage: ContextUsage) -> String {
        "\(usage.percent)%"
    }

    static func detailText(_ usage: ContextUsage) -> String {
        "Context \(formatTokens(usage.usedTokens)) / \(formatTokens(usage.limitTokens)) tokens (\(usage.percent)%)"
    }

    static func formatTokens(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.0fk", Double(value) / 1_000)
        }
        return "\(value)"
    }
}

/// Maps a model id to its context window. `reported` (from a live provider
/// catalog) always wins; otherwise an explicit window in the model id wins,
/// then the well-known windows of a family, and finally the configured
/// default (user directive: 200k context / 32k output when the provider
/// reports no metadata).
enum ContextWindowCatalog {
    /// Default context window when nothing is known about the model.
    static let fallbackLimit = 200_000

    /// Default output limit when nothing is known about the model.
    static let fallbackOutputLimit = 32_000

    static func limit(for modelID: String, reported: Int? = nil) -> Int {
        if let reported, reported > 0 { return reported }
        let id = modelID.lowercased()

        if let suffix = explicitWindow(in: id) { return suffix }

        // Documented windows — not guesses: these families have a fixed,
        // publicly known context size.
        if id.contains("gemini") { return 1_000_000 }
        if id.contains("claude") { return 200_000 }
        if id.contains("gpt-4.1") || id.contains("gpt-4o") || id.contains("gpt-4") { return 128_000 }
        return fallbackLimit
    }

    /// Output limit of a model: reported metadata wins, otherwise the default.
    static func outputLimit(for modelID: String, reported: Int? = nil) -> Int {
        if let reported, reported > 0 { return reported }
        let id = modelID.lowercased()
        if let suffix = explicitOutputWindow(in: id) { return suffix }
        return fallbackOutputLimit
    }

    /// Matches suffixes like `:32k`, `-128k`, `_1m`. Must run before family
    /// checks so `qwen2.5-coder:32k` does not inherit the generic default.
    private static func explicitWindow(in id: String) -> Int? {
        scaledWindow(in: id, pattern: #"[:@\-_](\d{1,4})k\b"#, multiplier: 1_024)
            ?? scaledWindow(in: id, pattern: #"[:@\-_](\d{1,2})m\b"#, multiplier: 1_000_000)
    }

    /// Matches an explicit output budget in the model id (`:32k`).
    private static func explicitOutputWindow(in id: String) -> Int? {
        scaledWindow(in: id, pattern: #"[:@\-_]out(\d{1,4})k\b"#, multiplier: 1_024)
    }

    private static func scaledWindow(in id: String, pattern: String, multiplier: Int) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)),
              let range = Range(match.range(at: 1), in: id),
              let value = Int(id[range]) else {
            return nil
        }
        return value * multiplier
    }
}
