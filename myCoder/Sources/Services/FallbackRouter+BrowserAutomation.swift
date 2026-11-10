import Foundation

extension FallbackRouter {
    /// Execute browser automation send
    static func executeBrowserAutomation(
        message: String,
        bridge: BrowserAutomationBridge,
        config: WebProviderConfig
    ) async -> SendAttempt {
        let startTime = Date()

        do {
            // Load catalog selectors for this vendor
            let catalog = try? WebProviderCatalog.loadBundled()
            let vendorEntry = catalog?.selectors(for: config.vendor.rawValue)

            let inputSelector = vendorEntry?.input
                ?? "textarea, [contenteditable='true'], .chat-input"
            let sendSelector = vendorEntry?.sendButton
                ?? "button[type='submit'], .send-button"

            // Audit 2026-09-09 (Kimi live): on a fresh webview the first
            // attempt typed 5 ms after resolve — the composer did not exist
            // yet and the attempt died instantly while the page needed
            // seconds to hydrate. Wait for the input to materialize first.
            var inputReady = false
            for _ in 0..<30 {
                if (try? await bridge.exists(selector: inputSelector)) == true {
                    inputReady = true
                    break
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            guard inputReady else {
                throw NSError(domain: "FallbackRouter", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "\(inputSelector) (chat input never appeared)"])
            }

            // Audit 2026-09-08: vendors convert oversized pastes into .txt
            // attachments (live: Kimi at ~4000 bytes silently turned the whole
            // tool-preamble into a file upload, so the model never saw the
            // text). Chunk the message with the same byte budget the
            // WebChatDriver path uses, typing every part and clicking send
            // only after the final one.
            let parts = WebPromptChunker.chunkedMessages(message)
            if parts.count > 1 { logger.log("BrowserAutomation: prompt split into \(parts.count) parts") }
            for (idx, part) in parts.enumerated() {
                logger.log("BrowserAutomation: typing into '\(inputSelector)' (no Enter — button-driven)")
                // Round 30: no synthetic Enter. On qwen.ai it CLEARS the input
                // instead of submitting; the verified button click below sends.
                try await bridge.typeText(part, into: inputSelector, humanized: false, pressEnter: false)
                logger.log("BrowserAutomation: typed, settling 700ms for framework state")
                try? await Task.sleep(nanoseconds: 700_000_000)

                // Non-final continuation parts must reach the model but do
                // not trigger generation. Audit 2026-09-09 (Qwen live): a
                // silent `try? click` here FAILED without anyone noticing —
                // part 1 (the tool-protocol preamble!) never reached the
                // model and the whole turn ran without tools. Every
                // continuation click is now verified the same way as the
                // final one: URL change or (inside an existing chat) the
                // composer emptying after the click. A failed continuation
                // click ABORTS the send — never stack part 2 on top of a
                // still-full composer.
                if idx < parts.count - 1 {
                    let contBeforeURL = (try? await bridge.currentURL()) ?? ""
                    guard await SendSubmissionPolicy.waitForSendEnabled(
                        bridge: bridge, sendSelector: sendSelector) else {
                        throw NSError(domain: "FallbackRouter", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: "\(sendSelector) (send button never enabled for continuation part \(idx + 1))"])
                    }
                    var contSubmitted = false
                    for _ in 0..<SendSubmissionPolicy.maxClickAttempts {
                        try await bridge.click(selector: sendSelector)
                        try? await Task.sleep(nanoseconds: UInt64(SendSubmissionPolicy.verifyDelayMs) * 1_000_000)
                        let contAfterURL = (try? await bridge.currentURL()) ?? contBeforeURL
                        let contButtonGone = (try? await bridge.exists(selector: sendSelector)) != true
                        let contEmptied = await Self.composerEmptied(
                            bridge: bridge, inputSelector: inputSelector, submittedText: part)
                        if SendSubmissionPolicy.submissionDetected(
                            beforeURL: contBeforeURL,
                            afterURL: contAfterURL,
                            sendButtonExistsAfterClick: !contButtonGone
                        ) || contEmptied {
                            contSubmitted = true
                            break
                        }
                    }
                    guard contSubmitted else {
                        throw NSError(domain: "FallbackRouter", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: "\(sendSelector) (continuation part \(idx + 1) was not submitted)"])
                    }
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    continue
                }
            }

            // Audit 2026-09-06: wait for the send button to MATERIALIZE
            // (Claude hydrates Tiptap + chat-input-send after the input
            // receives text; clicking a button that doesn't exist yet throws
            // elementNotFound and SmartSend gives up after 3 attempts).
            var sendReady = false
            for _ in 0..<20 {
                if (try? await bridge.exists(selector: sendSelector)) == true {
                    sendReady = true
                    break
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            guard sendReady else {
                logger.log("BrowserAutomation: send button never appeared for '\(sendSelector)'")
                throw NSError(domain: "FallbackRouter", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: sendSelector])
            }

            // Round 30: a click is an attempt, not proof. Verify the vendor
            // page actually submitted. Audit 2026-09-09 (Claude live): inside
            // an existing chat the URL NEVER changes and Claude KEEPS a
            // disabled send button in the DOM — the old signals missed every
            // real submit, retried, and posted the message 12 times. The
            // universal signal is the composer: it holds our text before the
            // click and empties on submit. URL change stays a fast path.
            // Audit 2026-09-09 (Qwen live): clicking before React commits
            // the typed text (button still disabled) submits nothing while
            // the composer then clears — wait for an enabled button first.
            let beforeURL = (try? await bridge.currentURL()) ?? ""
            let submittedText = parts.last ?? message
            guard await SendSubmissionPolicy.waitForSendEnabled(
                bridge: bridge, sendSelector: sendSelector) else {
                throw NSError(domain: "FallbackRouter", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "\(sendSelector) (send button never enabled after typing)"])
            }
            var verified = false
            for attempt in 1...SendSubmissionPolicy.maxClickAttempts {
                logger.log("BrowserAutomation: click attempt \(attempt)/\(SendSubmissionPolicy.maxClickAttempts) on '\(sendSelector)'")
                try await bridge.click(selector: sendSelector)
                try? await Task.sleep(nanoseconds: UInt64(SendSubmissionPolicy.verifyDelayMs) * 1_000_000)
                let afterURL = (try? await bridge.currentURL()) ?? beforeURL
                // Audit 2026-09-09: re-reading the button's presence AFTER the
                // click distinguishes "submitted inside an existing chat"
                // (button gone) from "click did nothing" (button still there).
                let buttonGone = (try? await bridge.exists(selector: sendSelector)) != true
                let composerEmptied = await Self.composerEmptied(
                    bridge: bridge, inputSelector: inputSelector, submittedText: submittedText)
                if SendSubmissionPolicy.submissionDetected(
                    beforeURL: beforeURL,
                    afterURL: afterURL,
                    sendButtonExistsAfterClick: !buttonGone
                ) || composerEmptied {
                    verified = true
                    logger.log("BrowserAutomation: submission verified (url='\(afterURL == beforeURL ? "same-conversation" : "changed")', button gone=\(buttonGone), composer emptied=\(composerEmptied))")
                    break
                }
                logger.log("BrowserAutomation: submission not verified yet (url unchanged)")
            }
            guard verified else {
                let duration = Date().timeIntervalSince(startTime)
                logger.log("BrowserAutomation: FAILED — page never confirmed submission after \(SendSubmissionPolicy.maxClickAttempts) clicks")
                return SendAttempt(
                    method: "browserAutomation",
                    success: false,
                    duration: duration,
                    error: "the provider page did not confirm sending (no remote chat id appeared)",
                    response: nil,
                    confidence: 0.0
                )
            }

            let duration = Date().timeIntervalSince(startTime)
            return SendAttempt(
                method: "browserAutomation",
                success: true,
                duration: duration,
                error: nil,
                response: nil,
                confidence: 0.5
            )
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            logger.log("BrowserAutomation FAILED: \(error.localizedDescription)")
            return SendAttempt(
                method: "browserAutomation",
                success: false,
                duration: duration,
                error: error.localizedDescription,
                response: nil,
                confidence: 0.0
            )
        }
    }

    /// Whether the composer no longer holds the just-submitted text (audit
    /// 2026-09-09, Claude live): inside an existing chat the URL never
    /// changes and some vendors keep a disabled send button in the DOM, so
    /// "composer emptied" is the universal submit signal. Reads both
    /// textarea values and contenteditable text; tiny/hidden mirrors are
    /// skipped so a stale clone cannot mask the real composer.
    static func composerEmptied(bridge: BrowserAutomationBridge,
                                        inputSelector: String,
                                        submittedText: String) async -> Bool {
        let probe = String(submittedText.prefix(120))
        let js = """
        (function(){
          var els = document.querySelectorAll(\(WebJSString.encode(inputSelector)));
          var want = \(WebJSString.encode(probe));
          for (var i = 0; i < els.length; i++) {
            var c = els[i];
            var r = c.getBoundingClientRect();
            if (r.width < 20 || r.height < 8) { continue; }
            var v = (c.value !== undefined) ? String(c.value) : String(c.innerText || '');
            if (v.indexOf(want) !== -1) { return false; }
          }
          return true;
        })();
        """
        return (try? await bridge.evaluateJS(js)) as? Bool ?? false
    }

    /// Find the best input element selector
    static func findInputElement(bridge: BrowserAutomationBridge) async -> String {
        // Try common input selectors
        let selectors = [
            "textarea",
            "[contenteditable='true']",
            ".chat-input",
            ".message-input",
            "input[type='text']",
            "[role='textbox']",
            ".composer",
            ".editor"
        ]

        for selector in selectors {
            let js = "document.querySelector('\(selector)') !== null"
            if let result = (try? await bridge.evaluateJS(js)) as? String,
               result == "true" {
                return selector
            }
        }

        return "textarea"
    }
}
