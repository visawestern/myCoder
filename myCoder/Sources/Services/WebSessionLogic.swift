import Foundation

/// Pure, testable session/captcha/anti-ban logic for web providers
/// (plan Раздел 12 Блок 3, testable parts). The actual browser I/O lives in
/// BrowserAutomationBridge (Playwright MCP); this file holds decisions.

/// State of a web-chat session as inferred from DOM/URL signals.
enum WebSessionState: Equatable {
    case connected
    case loggedOut          // redirected to login / chat field missing
    case captchaRequired    // captcha iframe/marker detected
    case limitReached       // vendor quota/paywall page (audit 2026-09-09)
    case unknown
}

/// Consecutive-confirmation box for vendor-limit detection (audit
/// 2026-09-09): a single poll can catch a transient hydration/navigation
/// flash, so the limit error throws only after N consecutive limit states
/// within one turn. Reference type so runTurn and awaitResponse share it.
final class LimitStabilityBox {
    /// Polls in a row that must agree before the limit error throws.
    static let requiredConfirmations = 3
    var consecutive = 0
}

/// Reference-type counter for session restarts due to token limits.
/// Used for progressive summarization thresholds: each restart increases
/// the allowed context window by `WebSessionSummarizer.stepTokens`.
final class RestartCountBox {
    var count: Int = 0
}

enum WebSessionLogic {

    /// Infer session state from observable signals (plan Блок 3 п.32/п.33).
    static func inferState(currentURL: String,
                          hasChatInput: Bool,
                          pageText: String) -> WebSessionState {
        if detectCaptcha(pageText: pageText, url: currentURL) {
            return .captchaRequired
        }
        // Audit 2026-09-09 (Kimi live): submitting on the /agent surface
        // with exhausted quota redirects to
        // /membership/pricing?from=okc_limit_notification. A pricing page
        // has no chat input — without this check it misreads as "logged
        // out" and the user is told to log in instead of hitting a limit.
        if detectLimitReached(pageText: pageText, url: currentURL) {
            return .limitReached
        }
        let lowerURL = currentURL.lowercased()
        if lowerURL.contains("/login") || lowerURL.contains("/signin") || lowerURL.contains("auth") {
            return .loggedOut
        }
        if !hasChatInput {
            return .loggedOut
        }
        return .connected
    }

    /// Detect a captcha challenge by well-known markers (plan Блок 3 п.33).
    static func detectCaptcha(pageText: String, url: String) -> Bool {
        let markers = [
            "recaptcha", "g-recaptcha", "hcaptcha", "h-captcha",
            "cf-turnstile", "cf-challenge", "challenges.cloudflare.com",
            "verify you are human", "verify you're human", "are you a robot",
            "i'm not a robot", "confirm you are human"
        ]
        let haystack = (pageText + " " + url).lowercased()
        return markers.contains { haystack.contains($0) }
    }

    /// Detect a vendor quota/paywall page (audit 2026-09-09, Kimi live).
    static func detectLimitReached(pageText: String, url: String) -> Bool {
        overloadKind(pageText: pageText, url: url) != .none
    }

    /// Classify a limit page: TRANSIENT overload notice (dismiss + wait +
    /// retry the same session) versus HARD quota wall (pricing redirect,
    /// exhausted quota — switch models or fail honestly).
    static func overloadKind(pageText: String, url: String) -> WebOverloadKind {
        let hardURLMarkers = [
            "/membership/pricing", "limit_notification", "limit-notification",
            "paywall", "membership", "pricing", "subscribe", "upgrade",
            "тариф", "подписк", "оплата"
        ]
        let hardTextMarkers = [
            "quota exceeded", "quota exhausted", "usage limit",
            "limit reached", "daily limit", "free quota",
            "upgrade to continue", "upgrade your plan",
            "membership required", "subscribe to continue",
            "превышен лимит", "лимит исчерпан", "оформите подписку"
        ]
        // Transient queue-gate banner (live 2026-09-09/11, Kimi):
        // "Too many people are chatting with Kimi right now. Subscribe for
        // the priority queue!" + RU "Слишком много людей сейчас общаются с
        // Kimi. Подпишитесь, чтобы попасть в специальную приоритетную
        // очередь!" with a Понятно dismiss button — sends CAN proceed once
        // it clears, so the session must be kept, not abandoned.
        let transientMarkers = [
            "too many people", "priority queue",
            "слишком много людей", "приоритетную очередь", "приоритетная очередь",
            "общаются с kimi", "chatting with kimi",
            "сейчас общаются с kimi"
        ]
        let lowerURL = url.lowercased()
        if hardURLMarkers.contains(where: { lowerURL.contains($0) }) {
            return .hard
        }
        let haystack = (pageText + " " + url).lowercased()
        if hardTextMarkers.contains(where: { haystack.contains($0) }) {
            return .hard
        }
        if transientMarkers.contains(where: { haystack.contains($0) }) {
            return .transient
        }
        return .none
    }

    /// Whether cookies indicate an expired/absent session (plan Блок 3 п.26).
    static func isSessionExpired(cookieExpiryEpochs: [TimeInterval], now: TimeInterval) -> Bool {
        guard !cookieExpiryEpochs.isEmpty else { return true }
        // Expired if every session cookie is already past its expiry.
        return cookieExpiryEpochs.allSatisfy { $0 <= now }
    }

    /// Whether a keep-alive ping is due (plan Блок 3 п.31).
    static func keepAliveDue(lastPing: TimeInterval, now: TimeInterval, intervalSec: Int) -> Bool {
        now - lastPing >= TimeInterval(intervalSec)
    }
}

/// What kind of vendor limit page is showing: a TRANSIENT overload notice
/// (Kimi "too many people" modal with a Понятно/Understood dismiss button —
/// audit 2026-09-11: just wait, dismiss, retry the same session) versus a
/// HARD quota wall (pricing redirect, exhausted quota — needs a model
/// switch or stays dead).
enum WebOverloadKind: Equatable {
    case none
    case transient
    case hard
}

/// Anti-ban / anti-captcha action delay with jitter (plan Раздел 12 Блок 2 п.22).
enum WebAntiBanTiming {
    /// Compute the delay (ms) for the next browser action, applying ±jitter%.
    /// `randomUnit` is an injectable [0,1) value for deterministic testing.
    static func delayMs(base: Int, jitterPercent: Double = 20, randomUnit: Double) -> Int {
        guard base > 0 else { return 0 }
        let clampedUnit = min(max(randomUnit, 0), 0.999999)
        let span = Double(base) * (jitterPercent / 100.0)
        // Map [0,1) to [-span, +span]
        let offset = (clampedUnit * 2 - 1) * span
        return max(0, Int((Double(base) + offset).rounded()))
    }

    /// Per-character human-typing delay (plan Блок 2 п.23).
    static func typingDelayMs(base: Int, randomUnit: Double) -> Int {
        delayMs(base: base, jitterPercent: 50, randomUnit: randomUnit)
    }
}
