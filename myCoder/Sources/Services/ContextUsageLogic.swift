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

    /// Per-model context windows imported from the user's `opencode.json`
    /// (`provider.<id>.models.<model>.limit.context`). Exact id match only, so
    /// a model not listed keeps the family/default behaviour. Mercury (the
    /// user's example) is pinned to 1M rather than the 200k fallback.
    static let opencodeContextWindows: [String: Int] = [
        "claude-fable-5": 1000000,
        "claude-fable-5.1": 1000000,
        "claude-haiku-4.5": 200000,
        "claude-opus-4.5": 200000,
        "claude-opus-4.6": 1000000,
        "claude-opus-4.7": 1000000,
        "claude-opus-4.8": 1000000,
        "claude-opus-5": 1000000,
        "claude-opus-5.5": 1000000,
        "claude-opus-latest": 1000000,
        "claude-sonnet-4.5": 200000,
        "claude-sonnet-4.6": 1000000,
        "claude-sonnet-5": 1000000,
        "claude-sonnet-latest": 1000000,
        "deepseek-v4-flash": 1048576,
        "deepseek-v4-flash-0731": 1310720,
        "deepseek-v4-flash-vision-exp": 1048576,
        "deepseek-v4-pro": 1048576,
        "deepseek-v4.1-flash": 1048576,
        "fugu-max": 1000000,
        "fugu-ultra-v2": 1000000,
        "gemini-3-pro-image": 131072,
        "gemini-3.1-flash-image": 131072,
        "gemini-3.1-flash-lite": 1048576,
        "gemini-3.1-flash-lite-image": 65536,
        "gemini-3.5-flash": 1048576,
        "gemini-3.5-flash-lite": 1048576,
        "gemini-3.6-flash": 1048576,
        "gemini-3.7-flash": 1048576,
        "gemini-3.8-flash": 1048576,
        "glm-5": 204800,
        "glm-5-turbo": 202752,
        "glm-5.1": 204800,
        "glm-5.2": 1048576,
        "glm-5.3": 1048576,
        "glm-5v-turbo": 202752,
        "gpt-4-turbo": 128000,
        "gpt-4.1": 1047576,
        "gpt-4.1-mini": 1047576,
        "gpt-4.1-nano": 1047576,
        "gpt-4o": 128000,
        "gpt-4o-mini": 128000,
        "gpt-5": 400000,
        "gpt-5-mini": 400000,
        "gpt-5-nano": 400000,
        "gpt-5.1": 400000,
        "gpt-5.2": 400000,
        "gpt-5.4": 1050000,
        "gpt-5.4-mini": 400000,
        "gpt-5.4-nano": 400000,
        "gpt-5.5": 1050000,
        "gpt-5.5-pro": 1050000,
        "gpt-5.6-luna": 1050000,
        "gpt-5.6-luna-pro": 1050000,
        "gpt-5.6-sol": 1050000,
        "gpt-5.6-terra": 1050000,
        "gpt-6-astra": 1050000,
        "gpt-6-luna": 1050000,
        "gpt-6-sol": 1050000,
        "gpt-chat-latest": 400000,
        "grok-4.6": 500000,
        "grok-4.7": 500000,
        "hy4-preview": 1048576,
        "inkling": 1048576,
        "inkling-small": 1048576,
        "kimi-k2.5": 262144,
        "kimi-k2.6": 262144,
        "kimi-k2.7-code": 262144,
        "ling-3.0-flash-fin": 262144,
        "mercury": 1000000,
        "mercury-2": 1000000,
        "mercury-3": 1000000,
        "muse-spark-1.1": 1048576,
        "muse-spark-1.2": 1048576,
        "muse-spark-1.2-contributor": 1048576,
        "muse-spark-1.3": 1048576,
        "muse-spark-1.3-contributor": 1048576,
        "nemotron-3-nano-30b-a3b": 262144,
        "nemotron-3-super-120b-a12b": 1000000,
        "nemotron-3.5-lightning": 262144,
        "nova-2-lite-v1": 1000000,
        "o3": 200000,
        "o3-mini": 200000,
        "o4-mini": 200000,
        "qwen3-omni-30b-a3b-thinking": 65536,
        "qwen3.5-9b": 262144,
        "qwen3.6-27b": 262144,
        "qwen3.7-flash": 1000000,
        "qwen3.7-max": 1000000,
        "qwen3.7-plus": 1000000,
        "qwen3.8-2.4t-a95b": 1048576,
        "qwen3.8-27b": 1000000,
        "qwen3.8-max": 1000000,
        "qwen3.8-max-0902": 1000000,
        "seed-2-1-turbo": 262144,
        "seed-2.0-code": 262144,
        "solar-pro4": 524288,
        "space-bunny-alpha": 1000000,
    ]

    /// Per-model output limits imported from the user's `opencode.json`.
    static let opencodeOutputWindows: [String: Int] = [
        "claude-fable-5": 128000,
        "claude-fable-5.1": 128000,
        "claude-haiku-4.5": 64000,
        "claude-opus-4.5": 64000,
        "claude-opus-4.6": 128000,
        "claude-opus-4.7": 128000,
        "claude-opus-4.8": 128000,
        "claude-opus-5": 128000,
        "claude-opus-5.5": 128000,
        "claude-opus-latest": 128000,
        "claude-sonnet-4.5": 64000,
        "claude-sonnet-4.6": 128000,
        "claude-sonnet-5": 128000,
        "claude-sonnet-latest": 128000,
        "deepseek-v4-flash": 384000,
        "deepseek-v4-flash-0731": 393216,
        "deepseek-v4-flash-vision-exp": 1048576,
        "deepseek-v4-pro": 393216,
        "deepseek-v4.1-flash": 393216,
        "fugu-max": 128000,
        "fugu-ultra-v2": 128000,
        "gemini-3-pro-image": 32768,
        "gemini-3.1-flash-image": 32768,
        "gemini-3.1-flash-lite": 65536,
        "gemini-3.1-flash-lite-image": 65536,
        "gemini-3.5-flash": 65536,
        "gemini-3.5-flash-lite": 65536,
        "gemini-3.6-flash": 65536,
        "gemini-3.7-flash": 65536,
        "gemini-3.8-flash": 65536,
        "glm-5": 128000,
        "glm-5-turbo": 131072,
        "glm-5.1": 128000,
        "glm-5.2": 131072,
        "glm-5.3": 131072,
        "glm-5v-turbo": 131072,
        "gpt-4-turbo": 4096,
        "gpt-4.1": 32768,
        "gpt-4.1-mini": 32768,
        "gpt-4.1-nano": 32768,
        "gpt-4o": 16384,
        "gpt-4o-mini": 16384,
        "gpt-5": 128000,
        "gpt-5-mini": 128000,
        "gpt-5-nano": 128000,
        "gpt-5.1": 128000,
        "gpt-5.2": 128000,
        "gpt-5.4": 128000,
        "gpt-5.4-mini": 128000,
        "gpt-5.4-nano": 128000,
        "gpt-5.5": 128000,
        "gpt-5.5-pro": 128000,
        "gpt-5.6-luna": 128000,
        "gpt-5.6-luna-pro": 128000,
        "gpt-5.6-sol": 128000,
        "gpt-5.6-terra": 128000,
        "gpt-6-astra": 128000,
        "gpt-6-luna": 128000,
        "gpt-6-sol": 128000,
        "gpt-chat-latest": 128000,
        "grok-4.6": 500000,
        "grok-4.7": 450000,
        "hy4-preview": 64000,
        "inkling": 262144,
        "inkling-small": 65536,
        "kimi-k2.5": 262144,
        "kimi-k2.6": 262144,
        "kimi-k2.7-code": 262144,
        "ling-3.0-flash-fin": 235929,
        "muse-spark-1.1": 16384,
        "muse-spark-1.2": 16384,
        "muse-spark-1.2-contributor": 16384,
        "muse-spark-1.3": 16384,
        "muse-spark-1.3-contributor": 16384,
        "nemotron-3-nano-30b-a3b": 262144,
        "nemotron-3-super-120b-a12b": 16384,
        "nemotron-3.5-lightning": 131072,
        "nova-2-lite-v1": 65535,
        "o3": 100000,
        "o3-mini": 100000,
        "o4-mini": 100000,
        "qwen3-omni-30b-a3b-thinking": 16384,
        "qwen3.5-9b": 262144,
        "qwen3.6-27b": 65536,
        "qwen3.7-flash": 65536,
        "qwen3.7-max": 131072,
        "qwen3.7-plus": 131072,
        "qwen3.8-2.4t-a95b": 262144,
        "qwen3.8-27b": 131072,
        "qwen3.8-max": 131072,
        "qwen3.8-max-0902": 131072,
        "seed-2-1-turbo": 262144,
        "seed-2.0-code": 131072,
        "solar-pro4": 131072,
        "space-bunny-alpha": 524288,
    ]

    static func limit(for modelID: String, reported: Int? = nil) -> Int {
        if let reported, reported > 0 { return reported }
        let id = modelID.lowercased()

        // Exact id match from the user's opencode.json reference dictionary
        // (loaded automatically by model name) wins over the static map and
        // the generic suffix/family rules, but still yields to `reported`.
        if let window = opencodeWindows[id], let context = window.context {
            return context
        }

        // Exact id match from the embedded opencode snapshot (fallback when the
        // live reference dictionary is unavailable).
        if let opencodeWindow = opencodeContextWindows[id] { return opencodeWindow }

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
        if let window = opencodeWindows[id], let output = window.output {
            return output
        }
        if let opencodeWindow = opencodeOutputWindows[id] { return opencodeWindow }
        if let suffix = explicitOutputWindow(in: id) { return suffix }
        return fallbackOutputLimit
    }

    // MARK: - OpenCode reference dictionary

    /// Path to the user's `opencode.json` reference dictionary. Tests can point
    /// this at a fixture; the production default is the standard location.
    static let defaultOpencodePath = OpenCodeModelWindows.defaultPath
    static var opencodeReferencePath: String = defaultOpencodePath

    /// Lazily parsed reference dictionary, invalidated when the path changes.
    private static var cachedOpencodePath: String?
    private static var cachedOpencodeWindows: [String: ModelWindow]?

    private static var opencodeWindows: [String: ModelWindow] {
        if cachedOpencodePath != opencodeReferencePath {
            cachedOpencodePath = opencodeReferencePath
            cachedOpencodeWindows = OpenCodeModelWindows.load(from: opencodeReferencePath)
        }
        return cachedOpencodeWindows ?? [:]
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
