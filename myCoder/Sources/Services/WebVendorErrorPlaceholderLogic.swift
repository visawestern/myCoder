import Foundation

/// Audit 2026-09-09 (Qwen live): when a vendor-side generation fails, the page
/// renders an ERROR PLACEHOLDER instead of a model answer (Qwen:
/// `div.response-message-empty` — "The current content is empty, please
/// regenerate."). The old code read that placeholder through the generic
/// `[class*='response']` fallback and presented it as the model's final
/// answer — fake success. This logic recognizes vendor error placeholders
/// (by element class and by text) so the bridge skips them, the driver never
/// finalizes on them, and the completion/API contracts reject them.
enum WebVendorErrorPlaceholderLogic {
    /// Class-name fragments of known vendor error/empty placeholders.
    /// Matched case-insensitively against an element's class attribute.
    static let errorClassFragments: [String] = [
        "response-message-empty",
        "message-empty",
        "message-error",
        "error-message",
        "response-error",
        "generate-error",
        "network-error",
        "send-failed",
        "message-failed"
    ]

    /// Text markers vendors render when no real answer was produced.
    /// Matched case-insensitively as substrings.
    static let errorTextMarkers: [String] = [
        "the current content is empty",
        "please regenerate",
        "something went wrong",
        "network error",
        "failed to generate",
        "generation failed",
        "message failed",
        "failed to send",
        "content was blocked",
        "response was stopped",
        "an error occurred",
        "oops, something",
        "try again later",
        "request failed",
        "service unavailable",
        "overloaded",
        "rate limit",
        "too many requests"
    ]

    /// True when the element's class marks it as a vendor error placeholder.
    static func isErrorElement(classAttribute: String) -> Bool {
        let lower = classAttribute.lowercased()
        return errorClassFragments.contains { lower.contains($0) }
    }

    /// True when the text is a vendor error placeholder rather than a model
    /// answer. Short safety: degenerate texts (< 4 chars) never match.
    static func isErrorPlaceholder(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return false }
        let lower = trimmed.lowercased()
        return errorTextMarkers.contains { lower.contains($0) }
    }

    /// True when the text may be presented as a genuine model answer:
    /// non-empty AND not a vendor error placeholder.
    static func isGenuineAnswer(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !isErrorPlaceholder(trimmed)
    }
}
