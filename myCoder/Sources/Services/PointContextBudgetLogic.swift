import Foundation

/// Full-window budget rules for point context (plan item 9).
///
/// Requirement: the final point-context prompt must NOT exceed the model's
/// FULL context window — the remaining window is irrelevant because every send
/// already carries the point context, and stale context is counted inside it.
/// Therefore:
///   • the evidence budget is `full window − fixed parts of THIS packet`
///     (system prompt + request); previously used chat volume is never
///     subtracted again;
///   • a packet fits when system + request + evidence ≤ full window;
///   • when the fixed parts already fill the window, evidence bytes dropped and
///     the honesty flag says so instead of pretending a fit.
///
/// Input: full model window (tokens), system-prompt tokens, content tokens.
/// Output: derived budgets and fit/truncation decisions.
/// Dependencies: `ContextUsageLogic.estimateTokens` (shared token heuristic).
enum PointContextBudgetLogic {

    /// Tokens the system prompt will consume (0 when absent).
    static func systemTokens(_ systemPrompt: String?) -> Int {
        guard let systemPrompt, !systemPrompt.isEmpty else { return 0 }
        return ContextUsageLogic.estimateTokens(systemPrompt)
    }

    /// Target prompt size for the whole packet: HALF the model window. The
    /// other half stays free for the model's answer (user directive
    /// 2026-11-13: compact the prompt to half the context so there is room to
    /// respond) — when the model context is smaller than the final prompt.
    static func contentTargetTokens(fullLimit: Int) -> Int {
        max(0, fullLimit / 2)
    }

    /// Evidence/content budget left by the FIXED parts of this packet.
    ///
    /// Input: full window; system-prompt tokens.
    /// Output: `max(0, half(full) − system)`. No "used chat volume" input
    /// exists by design: previously used tokens must not shrink this packet's
    /// budget, and the packet target is half the full window so the model
    /// always has room to answer.
    static func remainingForContent(fullLimit: Int, systemTokens: Int) -> Int {
        max(0, contentTargetTokens(fullLimit: fullLimit) - max(0, systemTokens))
    }

    /// Whether the whole packet (system + content) fits the full window.
    static func fits(fullLimit: Int, systemTokens: Int, contentTokens: Int) -> Bool {
        systemTokens + contentTokens <= fullLimit
    }

    /// Whether evidence must be dropped because the fixed parts alone fill the
    /// window (request/system are never shortened — only evidence is).
    static func shouldDropEvidence(fullLimit: Int, systemTokens: Int) -> Bool {
        systemTokens >= fullLimit
    }

    /// Estimate of the complete packet in tokens: system + request + evidence.
    ///
    /// Input: system prompt, request text, evidence text, chat-history text.
    /// Output: conservative token estimate (same heuristic as the UI badge).
    /// Dependencies: `ContextUsageLogic.estimateTokens`.
    static func estimatedPacketTokens(systemPrompt: String?,
                                      request: String,
                                      evidenceText: String,
                                      historyText: String = "") -> Int {
        var total = 0
        total += systemTokens(systemPrompt)
        total += ContextUsageLogic.estimateTokens(request)
        total += ContextUsageLogic.estimateTokens(evidenceText)
        total += ContextUsageLogic.estimateTokens(historyText)
        return total
    }

    /// Convert a token budget to the byte budget the compiler works in.
    static func budgetBytes(tokens: Int) -> Int {
        max(0, tokens) * TurnContextCompiler.bytesPerToken
    }
}
