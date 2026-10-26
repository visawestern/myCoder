import Foundation

/// Contract for the paste-verify input protocol in WKWebViewBrowserBridge.
///
/// Live audit 2026-09-08: vendor editors (Kimi, Claude/Tiptap) accept a
/// ClipboardEvent('paste') but Kimi renders the inserted text
/// ASYNCHRONOUSLY (~100–300 ms after the dispatch), and Kimi restores
/// unsent drafts into the composer between page loads. Therefore the
/// bridge must (1) dispatch the paste, (2) re-check the field content from
/// Swift over a bounded window BEFORE running any fallback insertion, so
/// a successful async paste is never duplicated by execCommand and a
/// failed one is retried instead of silently corrupting the message.
enum WebComposerInputPolicy {
    /// Delay between content re-checks while waiting for an async paste to
    /// render in the composer.
    static let verifyDelayMs: Int = 200

    /// Re-checks per insertion stage — 6 × 200 ms = a 1.2 s budget,
    /// comfortably above the ~300 ms worst-case render observed on Kimi.
    static let verifyAttempts: Int = 6
}
