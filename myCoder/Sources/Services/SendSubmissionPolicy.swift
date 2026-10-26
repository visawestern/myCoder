import Foundation

/// Round 30 — submission verification for browser-automation sends.
///
/// A single `click()` on the send control is NOT proof that the vendor page
/// submitted: on a freshly hydrated page the click can land before React binds
/// the handler, and the old code reported success anyway. Submission is instead
/// VERIFIED by observing the page URL gain a remote chat id (`/chat/{id}` on
/// Kimi/Qwen, `/c/{id}` on ChatGPT) after the click; if it does not appear
/// within the retry budget, the click repeats and finally fails honestly.
enum SendSubmissionPolicy {
    static let maxClickAttempts = 3
    static let verifyDelayMs = 1200

    /// Round 30b: bounded retries for model/effort menu matching. Menus can
    /// render late (fresh page, post-submission navigation), so a failed match
    /// re-opens the menu and tries again instead of one-shot failing.
    static let maxMatchRetries = 3
    static let matchRetryDelayMs = 800

    /// True only when the URL CHANGED and now carries a chat id segment.
    static func submissionDetected(beforeURL: String, afterURL: String) -> Bool {
        guard afterURL != beforeURL else { return false }
        return urlHasChatID(afterURL)
    }

    /// Audit 2026-09-09 (ChatGPT live): sending a message INSIDE an existing
    /// conversation (`/c/{id}`) does NOT change the URL — the URL-only check
    /// kept "verifying" forever, re-clicked send and finally reported failure
    /// although the first click had already submitted (the send button
    /// disappears once the composer empties). A vanished send button after a
    /// click is a second, independent submission signal for exactly this
    /// already-in-conversation case; a still-present button proves nothing.
    static func submissionDetected(beforeURL: String,
                                    afterURL: String,
                                    sendButtonExistsAfterClick: Bool) -> Bool {
        if submissionDetected(beforeURL: beforeURL, afterURL: afterURL) {
            return true
        }
        // Only trust the vanished-button signal when the URL already hosts a
        // conversation: on a FRESH chat page the button also vanishes while
        // the URL is still settling, and that would be a false positive.
        guard urlHasChatID(afterURL), afterURL == beforeURL else { return false }
        return !sendButtonExistsAfterClick
    }

    /// Whether a URL contains a plausible remote chat id (`/chat/` or `/c/`
    /// followed by a segment of at least 8 characters — real ids are UUIDs or
    /// long tokens; short junk like "short" must not count).
    static func urlHasChatID(_ url: String) -> Bool {
        for pattern in ["/chat/", "/c/"] {
            guard let range = url.range(of: pattern) else { continue }
            let part = url[range.upperBound...]
                .split(whereSeparator: { $0 == "/" || $0 == "?" || $0 == "#" })
                .first.map(String.init) ?? ""
            if part.count >= 8 { return true }
        }
        return false
    }

    /// Wait until the send control is present AND enabled (audit 2026-09-09,
    /// Qwen live): typing returns as soon as the text verifies in the DOM,
    /// but React commits its state asynchronously — clicking the still-
    /// disabled button submits nothing while the composer then clears,
    /// which the composer-emptied check misreads as a successful submit and
    /// the message is silently lost. Worse (Qwen live, 2000-char preamble):
    /// the DOM holds the pasted text while React state is still empty, and
    /// React's commit then WIPES the DOM text — a click in that window
    /// submits emptiness and the message vanishes without any error. So the
    /// button must read enabled on TWO successive polls (~200 ms apart),
    /// proving React committed the text, not just rendered a frame of it.
    /// A `nil`/non-Bool evaluation (test fakes return canned values; live
    /// JS errors) counts as ready — the click itself then validates honestly
    /// instead of hanging the turn.
    static func waitForSendEnabled(bridge: BrowserAutomationBridge,
                                   sendSelector: String,
                                   timeoutMs: Int = 5000) async -> Bool {
        let js = """
        (function(){
          var el = document.querySelector(\(WKWebViewBrowserBridge.jsString(sendSelector)));
          if(!el){return false;}
          var target = el.matches('button, [role="button"], input[type="submit"]')
            ? el
            : (el.querySelector('button, [role="button"], input[type="submit"]') || el);
          if (target.disabled || target.getAttribute('aria-disabled') === 'true') { return false; }
          var r = target.getBoundingClientRect();
          if (r.width < 8 || r.height < 8) { return false; }
          return true;
        })();
        """
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        var stableReads = 0
        while Date() < deadline {
            let ready = try? await bridge.evaluateJS(js)
            guard let enabled = ready as? Bool else { return true }
            if enabled {
                stableReads += 1
                if stableReads >= 2 { return true }
            } else {
                stableReads = 0
            }
            await bridge.wait(ms: 200)
        }
        return false
    }
}
