import Foundation

extension WebChatDriver {
    /// Wait until generation finishes: the stop button disappears and the
    /// response text is stable across `stabilityChecks` polls (plan Блок 2 п.24).
    /// `sentText` is the just-submitted user text: while generation was never
    /// observed (no stop control seen this turn), a stable readout that
    /// merely echoes it is our own message rendering — not the answer
    /// (audit 2026-09-08, Kimi). Once generation ran, whatever remains stable
    /// is the answer, even if it quotes the prompt.
    func awaitResponse(after baseline: ResponseBaseline,
                               emit: (WebChatEvent) -> Void,
                               sentText: String = "",
                               limitStability: LimitStabilityBox) async throws -> String {
        var lastText = baseline.text
        var lastFingerprint = baseline.fingerprint
        var stableCount = 0
        var hasNonEmptyResponse = false
        var observedNewResponse = false
        var stopSeen = false
        // Kimi limit/overload events are routed to the outer loop (model
        // switch or dismiss-and-retry) — surfacing them once here instead of
        // killing the turn with a misleading logged-out error.
        var emittedKimiInterruption = false
        // Bound the wait to avoid infinite loops on a broken page.
        let maxPolls = 600  // pollIntervalMs * 600 = up to 2 min at 200ms
        var polls = 0
        print("🔄 [WebChatDriver] awaitResponse started, baseline_text_len=\(baseline.text.count), maxPolls=\(maxPolls)")
        while polls < maxPolls {
            try Task.checkCancellation()
            if let interruption = try await checkInterruptions(emit: emit, limitStability: limitStability) {
                if case .captchaDetected = interruption {
                    emit(interruption)
                    try await waitForCaptchaResolution(emit: emit)
                } else if case .kimiQuotaExhausted = interruption {
                    // Handled by the outer loop on the next iteration (the
                    // shared stability box already confirmed it).
                    if !emittedKimiInterruption {
                        emittedKimiInterruption = true
                        emit(interruption)
                    }
                    throw WebChatError.kimiInterrupted
                } else if case .kimiOverloaded = interruption {
                    // Same routing as quota: dismiss-and-retry in the loop.
                    if !emittedKimiInterruption {
                        emittedKimiInterruption = true
                        emit(interruption)
                    }
                    throw WebChatError.kimiInterrupted
                } else {
                    emit(interruption)
                    throw WebChatError.sessionLoggedOut
                }
            }

            let generating = (try? await bridge.exists(selector: selectors.stopButton)) ?? false
            if generating { stopSeen = true }
            let text = (try? await readLatestResponse()) ?? lastText
            let fingerprint = (try? await bridge.responseFingerprint(selector: selectors.responseContainer)) ?? text
            let changed = text != baseline.text || fingerprint != baseline.fingerprint
            let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if polls % 50 == 0 {
                print("🔄 [WebChatDriver] poll \(polls): generating=\(generating), text_len=\(text.count), changed=\(changed), normalized_len=\(normalized.count)")
            }
            if !normalized.isEmpty && changed {
                hasNonEmptyResponse = true
                observedNewResponse = true
            }
            if text != lastText || fingerprint != lastFingerprint {
                if observedNewResponse { emit(.streaming(text)) }
                lastText = text
                lastFingerprint = fingerprint
                stableCount = 0
            } else if !generating && hasNonEmptyResponse && observedNewResponse {
                // Own-message echo is not an answer until generation ran.
                if !stopSeen, WebChatEchoLogic.isEcho(normalized, of: sentText) {
                    await bridge.wait(ms: pollIntervalMs)
                    polls += 1
                    continue
                }
                stableCount += 1
                if stableCount >= stabilityChecks { return lastText }
            }
            await bridge.wait(ms: pollIntervalMs)
            polls += 1
        }
        // Audit 2026-09-09 (ChatGPT live): a finished answer can sit in the
        // DOM UNRENDERED (React keeps the text nodes virtual in a background
        // webview; markers like data-end are already committed while innerText
        // stays empty — verified by reloading the page, which rendered the
        // full answer). Before giving up: if the response container shows
        // completion markers but no readable text, reload the page once and
        // read the answer from the freshly rendered conversation.
        if lastText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !observedNewResponse {
            if let recovered = try? await recoverRenderedAnswerAfterTimeout(baseline: baseline) {
                return recovered
            }
        }
        // An unchanged empty DOM is a failed send/response, not a valid answer.
        // Surface a timeout so the caller can retry the browser path instead of
        // presenting the misleading "model returned empty response" message.
        MyCoderAPIServer.appendLog("⏱️ [WebChatDriver] awaitResponse timeout: lastText_len=\(lastText.count), observedNew=\(observedNewResponse)")
        throw WebChatError.responseTimeout
    }

    /// Last-mile recovery for the unrendered-answer case: reload the current
    /// conversation, wait for the response container, and read the answer.
    /// The recovered text must DIFFER from the pre-send baseline so a stale
    /// previous answer (re-rendered by the reload) is never reported as this
    /// turn's answer. Returns nil when nothing new appears, leaving the
    /// caller to fail with its normal timeout semantics.
    func recoverRenderedAnswerAfterTimeout(baseline: ResponseBaseline) async throws -> String? {
        guard let url = try? await bridge.currentURL(), !url.isEmpty else { return nil }
        do {
            _ = try await bridge.evaluateJS("location.reload(); true;")
        } catch {
            MyCoderAPIServer.appendLog("🔁 [WebChatDriver] reload failed: \(error.localizedDescription)")
        }
        for _ in 0..<40 { // up to 20 s for the reloaded conversation
            try Task.checkCancellation()
            await bridge.wait(ms: 500)
            if let text = try? await readLatestResponse(),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               text != baseline.text {
                return text
            }
        }
        return nil
    }

    // Read the last assistant message from the DOM. Tries the vendor-specific
    // response container first, then falls back to common selectors so we do
    // not falsely report "empty response" while the page is still hydrating.
    func readLatestResponse() async throws -> String {
        let raw = try await readLatestResponseRaw()
        // Audit 2026-09-12 (last chat): vendor code-chrome junk ("tool" chip,
        // "Копировать" copy button) is scraped as standalone lines around
        // fenced blocks. Strip it once here — every consumer (streaming,
        // final answer, tool-call parsing, echo guard) gets clean text, and
        // the tool parser itself is unaffected because chrome lines were
        // never valid JSON anyway.
        return WebScrapedTextSanitizer.sanitizeStreaming(raw)
    }

    func readLatestResponseRaw() async throws -> String {
        if let primary = (try? await bridge.readText(selector: selectors.responseContainer)), !primary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return primary
        }
        let fallbacks = [
            "div[data-message-author-role='assistant']",
            ".markdown-body",
            "[class*='markdown']",
            "[class*='response']",
            "[class*='message-content']"
        ]
        for selector in fallbacks {
            if let text = (try? await bridge.readText(selector: selector)), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }
        return ""
    }

    /// Detect captcha / logout / vendor limit before proceeding (plan Блок 3
    /// п.32/п.34; limit audit 2026-09-09).
    ///
    /// Limit pages throw ONLY after `limitStability` consecutive confirmations:
    /// a single poll can catch a transient hydration/navigation flash (live:
    /// a Claude turn died spuriously on one poll while the next turn on the
    /// same page answered fine). Captcha/logout stay immediate — those states
    /// are sticky, limit banners are not.
    func checkInterruptions(emit: (WebChatEvent) -> Void,
                                    limitStability: LimitStabilityBox) async throws -> WebChatEvent? {
        let url = (try? await bridge.currentURL()) ?? ""
        let pageText = (try? await bridge.pageText()) ?? ""
        let hasInput = (try? await bridge.exists(selector: selectors.input)) ?? true
        switch WebSessionLogic.inferState(currentURL: url, hasChatInput: hasInput, pageText: pageText) {
        case .captchaRequired:
            let png = (try? await bridge.screenshot(selector: nil)) ?? Data()
            return .captchaDetected(screenshotPNG: png)
        case .loggedOut:
            return .loggedOut
        case .limitReached:
            limitStability.consecutive += 1
            guard limitStability.consecutive >= LimitStabilityBox.requiredConfirmations else {
                return nil
            }
            // Kimi: split TRANSIENT overload ("too many people" modal with a
            // Понятно button — dismiss, wait, retry the SAME session) from a
            // HARD quota wall (pricing redirect / exhausted quota — switch to
            // Fast once). K3-family models are treated as hard: K3 is
            // persistently overloaded, waiting never clears it.
            if config.vendor.id == "kimi", !config.selectedModel.isEmpty {
                let kind = WebSessionLogic.overloadKind(pageText: pageText, url: url)
                let isAgent = WebChatSurfaceLogic.isKimiAgentModel(config.selectedModel, vendor: config.vendor)
                if kind == .hard || (kind != .none && isAgent) {
                    return .kimiQuotaExhausted
                }
                return .kimiOverloaded
            }
            // Other vendors: honest terminal error.
            throw WebChatError.providerLimitReached(
                "The provider reports its usage limit is reached (quota/paywall page). Check the subscription or quota, then retry.")
        case .connected, .unknown:
            limitStability.consecutive = 0
            return nil
        }
    }

    /// Single-poll quota check for the turn-start proactive Kimi switch
    /// (audit 2026-09-11): K3 is persistently overloaded, so a page that
    /// already shows quota markers must not burn a send on K3 first. No
    /// stability box — a false positive only costs a switch to the usable
    /// Fast model, and SmartSend-submitted turns never reach this path.
    func kimiQuotaImmediatelyVisible() async -> Bool {
        let url = (try? await bridge.currentURL()) ?? ""
        let pageText = (try? await bridge.pageText()) ?? ""
        let hasInput = (try? await bridge.exists(selector: selectors.input)) ?? true
        return WebSessionLogic.inferState(currentURL: url, hasChatInput: hasInput, pageText: pageText) == .limitReached
    }
}
