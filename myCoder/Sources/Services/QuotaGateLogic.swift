import Foundation

/// Pure, deterministic budget math for per-minute request/token quotas
/// (directive 2026-11-13: per-model, per-provider cross-chat and per-API-key
/// limits + token quotas like Google's ~250k tokens/min; all default off).
///
/// A quota is a fixed 60-second window counted from an epoch-aligned boundary
/// (the start of the minute containing `now`): a window starts at
/// floor(now / 60) * 60 and ends 60 s later. Usage recorded in an earlier
/// window is irrelevant to the current one, so the limiter self-resets every
/// minute without any timer.
///
/// Input: a `QuotaPolicy` (limits; 0 = unlimited), the current window usage,
/// the request weight and token estimate.
/// Output: allow/deny answers, wait seconds, and the updated window after an
/// allowed acquisition.
/// Dependencies: none (Foundation Date only), fully unit-testable.
enum QuotaGateLogic {

    /// Seconds per window. Fixed at 60 for every limit kind.
    static let windowSeconds: TimeInterval = 60

    /// One fixed 60-second usage window.
    struct Window: Equatable {
        /// Epoch seconds of the window's start (multiple of 60).
        var start: Double
        var usedRequests: Int
        var usedTokens: Int
    }

    /// Limits for one scope (provider / model / key). 0 means unlimited.
    struct Policy: Equatable {
        var requestLimit: Int
        var tokenQuota: Int

        static let unlimited = Policy(requestLimit: 0, tokenQuota: 0)

        var hasAnyLimit: Bool { requestLimit > 0 || tokenQuota > 0 }
    }

    /// The window covering `now` (epoch-aligned minute boundary).
    static func currentWindow(now: Date = Date()) -> Window {
        let epoch = now.timeIntervalSince1970
        let start = floor(epoch / windowSeconds) * windowSeconds
        return Window(start: start, usedRequests: 0, usedTokens: 0)
    }

    /// True when the window for `now` is still the one `window` belongs to
    /// (false → the window aged out and a fresh one must be used).
    static func isCurrent(_ window: Window, now: Date = Date()) -> Bool {
        window.start == currentWindow(now: now).start
    }

    /// Whether an acquisition of `requestCount` requests consuming roughly
    /// `tokenEstimate` tokens fits inside `policy` given `window` usage.
    ///
    /// Input: policy, window, request count (≥1), token estimate (≥0).
    /// Output: true when both dimensions stay under their configured limits.
    /// Dependencies: none.
    static func allows(policy: Policy,
                       window: Window,
                       requestCount: Int = 1,
                       tokenEstimate: Int = 0) -> Bool {
        if policy.requestLimit > 0, window.usedRequests + requestCount > policy.requestLimit {
            return false
        }
        if policy.tokenQuota > 0, window.usedTokens + tokenEstimate > policy.tokenQuota {
            return false
        }
        return true
    }

    /// Seconds until the blocking dimension frees up. With a 60 s fixed window
    /// the wait is always (window end − now) when a limit is already reached;
    /// returns 0 when the acquisition is allowed right now.
    ///
    /// Input: policy, window, now, request count and token estimate.
    /// Output: 0 when allowed; otherwise whole seconds to the window end.
    /// Dependencies: `allows`, `currentWindow`.
    static func waitSeconds(policy: Policy,
                            window: Window,
                            now: Date = Date(),
                            requestCount: Int = 1,
                            tokenEstimate: Int = 0) -> Int {
        guard policy.hasAnyLimit,
              !allows(policy: policy, window: window,
                      requestCount: requestCount, tokenEstimate: tokenEstimate) else {
            return 0
        }
        let end = window.start + windowSeconds
        return max(1, Int(ceil(end - now.timeIntervalSince1970)))
    }

    /// The window after an allowed acquisition (usedRequests + requestCount,
    /// usedTokens + tokenEstimate). Callers must have checked `allows` first.
    static func acquiring(_ window: Window,
                          requestCount: Int = 1,
                          tokenEstimate: Int = 0) -> Window {
        Window(start: window.start,
               usedRequests: window.usedRequests + requestCount,
               usedTokens: window.usedTokens + tokenEstimate)
    }

    /// The window after reporting real token usage from a response (never
    /// negative; actual usage may be lower than the pre-flight estimate).
    static func recording(_ window: Window, tokens: Int) -> Window {
        Window(start: window.start,
               usedRequests: window.usedRequests,
               usedTokens: max(0, window.usedTokens + tokens))
    }

    /// Estimate of the prompt tokens a request of `contextBytes` will consume:
    /// about 4 bytes per token, plus the configured max output tokens.
    static func estimatedTokens(contextBytes: Int, maxOutputTokens: Int? = nil) -> Int {
        let prompt = max(1, contextBytes / 4)
        return prompt + (maxOutputTokens ?? 0)
    }
}

/// A single limit scope's live budget state, exposed for the settings UI
/// (“online accounting”: which API key is active, how much of the minute's
/// allowance remains).
struct QuotaScopeStatus: Equatable {
    let scopeKey: String
    let kind: QuotaScopeKind
    /// Seconds until the current window resets (0 = fresh window).
    let resetSeconds: Int
    /// Remaining requests this window (nil = unlimited).
    let remainingRequests: Int?
    /// Remaining tokens this window (nil = unlimited).
    let remainingTokens: Int?
}

enum QuotaScopeKind: String, Equatable {
    case provider
    case model
    case apiKey
}

/// Human-readable wait message the app writes to the chat while it waits:
/// “Rate limit 10 req/min reached — waiting…” / “Token quota 250000/min
/// reached — waiting…”. Localized for the app's selected language (all 10
/// languages). Pure formatting, fully testable — `language` defaults to the
/// current runtime language so callers never have to pass it.
enum QuotaWaitMessage {
    static func requestLimit(limit: Int, waitSeconds: Int,
                             language: AppLanguage = LocalizationRuntime.currentLanguage) -> String {
        let template = AppLocalization.string(
            forEnglish: "Rate limit %@ requests/min reached — waiting %@s",
            language: language
        )
        return String(format: template, String(limit), String(waitSeconds))
    }

    static func tokenQuota(quota: Int, waitSeconds: Int,
                           language: AppLanguage = LocalizationRuntime.currentLanguage) -> String {
        let template = AppLocalization.string(
            forEnglish: "Token quota %@/min reached — waiting %@s",
            language: language
        )
        return String(format: template, String(quota), String(waitSeconds))
    }

    static func allKeysExhausted(waitSeconds: Int,
                                 language: AppLanguage = LocalizationRuntime.currentLanguage) -> String {
        let template = AppLocalization.string(
            forEnglish: "All API keys exhausted — waiting %@s",
            language: language
        )
        return String(format: template, String(waitSeconds))
    }
}
