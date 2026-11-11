import Foundation

extension WebChatDriver {
    // MARK: - Steps

    /// Wait for the user to solve a captcha in the same live browser page.
    /// The chat turn remains in the driver; no duplicate prompt or new remote
    /// chat is created. A logout aborts the turn and a bounded timeout avoids a
    /// permanently suspended task.
    func waitForCaptchaResolution(emit: (WebChatEvent) -> Void) async throws {
        let maxPolls = 600 // five minutes at 500 ms
        for _ in 0..<maxPolls {
            try Task.checkCancellation()
            await bridge.wait(ms: 500)
            let url = (try? await bridge.currentURL()) ?? ""
            let pageText = (try? await bridge.pageText()) ?? ""
            let hasInput = (try? await bridge.exists(selector: selectors.input)) ?? false
            let state = WebSessionLogic.inferState(
                currentURL: url,
                hasChatInput: hasInput,
                pageText: pageText
            )
            switch WebCaptchaResolutionLogic.action(for: state) {
            case .resume:
                return
            case .abort:
                emit(.loggedOut)
                throw WebChatError.captchaResolutionAborted
            case .wait:
                continue
            }
        }
        throw WebChatError.captchaResolutionTimedOut
    }

    /// Send a message, splitting a large PROMPT into several messages so we don't
    /// overload the web model / hit its session length limit (plan Раздел 12
    /// extension). Non-final parts use the continuation protocol so the model
    /// waits before responding; only the final part triggers generation.
    func sendPossiblyChunked(_ text: String, emit: (WebChatEvent) -> Void) async throws -> ResponseBaseline {
        let parts = WebPromptChunker.chunkedMessages(text)
        if parts.count > 1 { emit(.promptSplit(parts: parts.count)) }
        var baseline = ResponseBaseline(text: "", fingerprint: "")
        for (idx, part) in parts.enumerated() {
            baseline = try await sendMessage(part, emit: emit)
            // For non-final continuation parts, wait briefly for the message to
            // register but do NOT wait for a full generation (model is instructed
            // to hold its answer until the final part).
            if idx < parts.count - 1 {
                await bridge.wait(ms: max(config.toolCallDelayMs, 300))
            }
        }
        return baseline
    }

    /// Type and submit one message. The returned text is the response already
    /// present before this submit; awaitResponse uses it as a baseline so an
    /// empty/old DOM node can never be reported as the new answer.
    ///
    /// Audit 2026-09-09 (ChatGPT live): vendor UI re-renders can drop the
    /// send button between typing and clicking (button present at the guard,
    /// absent at click) while our text sits in the composer. The click is
    /// retried once after a beat; if the composer emptied meanwhile the
    /// message went out by another path (Enter/submit race) and the send
    /// counts as done — never throw "not sent" for a delivered message,
    /// never click blindly into a re-render.
    func sendMessage(_ text: String, emit: (WebChatEvent) -> Void) async throws -> ResponseBaseline {
        guard (try? await bridge.exists(selector: selectors.input)) == true else {
            throw WebChatError.selectorNotFound(selectors.input)
        }
        let baselineText = (try? await readLatestResponse()) ?? ""
        let baselineFingerprint = (try? await bridge.responseFingerprint(selector: selectors.responseContainer)) ?? baselineText
        await antiBanDelay()
        // Audit 2026-09-09 (Claude live): pressEnter=true let a synthetic
        // Enter SUBMIT the message, and the button click right after threw
        // "disabled" on the emptied composer — the turn died with an error
        // although the message was delivered (tool_result reached the model,
        // which answered, but locally we recorded failure). Button-driven
        // sends only (Round 30: SmartSend does the same); a click failure
        // then honestly means "not sent".
        try await bridge.typeText(text, into: selectors.input, humanized: config.toolCallDelayMs > 0, pressEnter: false)
        await antiBanDelay()
        // Audit 2026-09-09 (ChatGPT live): the send button materializes
        // only AFTER text lands in the composer (empty composer = no button
        // in DOM), and right after an answer the UI re-render drops it
        // transiently. So: type FIRST, then wait boundedly for a present
        // AND enabled button (FallbackRouter order) — never demand the
        // button upfront. Audit 2026-09-09 (Qwen live): clicking the
        // still-disabled button (React state lagging the DOM) submits
        // nothing while the composer then clears — a silent loss.
        let sendReady = await SendSubmissionPolicy.waitForSendEnabled(
            bridge: bridge, sendSelector: selectors.sendButton, timeoutMs: sendEnabledTimeoutMs)
        guard sendReady else {
            throw WebChatError.selectorNotFound("\(selectors.sendButton) (send button never materialized or stayed disabled)")
        }
        do {
            try await bridge.click(selector: selectors.sendButton)
        } catch {
            // One bounded retry after a UI re-render beat.
            await bridge.wait(ms: 1200)
            if await composerStillHolds(text) {
                try await bridge.click(selector: selectors.sendButton)
            }
            // Composer emptied without our click landing: the message went
            // out (submit race / Enter) — proceed to await its response.
        }
        return ResponseBaseline(text: baselineText, fingerprint: baselineFingerprint)
    }

    /// Whether the composer still holds our just-typed text (same visibility
    /// rule as the bridge: tiny hidden mirrors don't count).
    func composerStillHolds(_ text: String) async -> Bool {
        let probe = String(text.prefix(120))
        let js = """
        (function(){
          var els = document.querySelectorAll(\(WebJSString.encode(selectors.input)));
          var want = \(WebJSString.encode(probe));
          for (var i = 0; i < els.length; i++) {
            var c = els[i];
            var r = c.getBoundingClientRect();
            if (r.width < 20 || r.height < 8) { continue; }
            var v = (c.value !== undefined) ? String(c.value) : String(c.innerText || '');
            if (v.indexOf(want) !== -1) { return true; }
          }
          return false;
        })();
        """
        return (try? await bridge.evaluateJS(js)) as? Bool ?? true
    }

    /// Extract the full conversation transcript from the browser DOM for
    /// summarization. Reads all user and assistant message elements and
    /// concatenates them into a compact text format. Vendor-specific
    /// selectors handle Qwen/Kimi/ChatGPT/Claude DOM structures.
    func extractTranscriptFromDOM() async -> String {
        // Generic extraction: try common author-role attributes first, then
        // fall back to main.innerText if no structured elements are found.
        let js = """
        (function(){
          var parts = [];
          // Strategy 1: data-message-author-role (ChatGPT, Claude)
          var userEls = document.querySelectorAll('[data-message-author-role="user"]');
          var asstEls = document.querySelectorAll('[data-message-author-role="assistant"]');
          if (userEls.length > 0 || asstEls.length > 0) {
            // Interleave by DOM order (messages alternate user/assistant).
            var all = [];
            userEls.forEach(function(el){ all.push({role:'user', el:el}); });
            asstEls.forEach(function(el){ all.push({role:'assistant', el:el}); });
            all.sort(function(a,b){
              return a.el.compareDocumentPosition(b.el) & Node.DOCUMENT_POSITION_FOLLOWING ? -1 : 1;
            });
            for (var i = 0; i < all.length; i++) {
              var t = (all[i].el.textContent || '').trim();
              if (t.length > 0) {
                parts.push(all[i].role.toUpperCase() + ': ' + t.substring(0, 4000));
              }
            }
          }
          if (parts.length > 0) return parts.join('\\n\\n');
          // Strategy 2: main.innerText fallback (Qwen, Kimi)
          var main = document.querySelector('main');
          return main ? main.innerText.substring(0, 100000) : '';
        })()
        """
        return (try? await bridge.evaluateJS(js)) as? String ?? ""
    }

    /// Restart the web session after a length-limit response, seeding a fresh
    /// chat with the tool preamble + goal + a compact recent summary so work
    /// continues instead of failing (plan Раздел 12 extension).
    func restartSessionWithCarryOver(lastResponse: String, emit: (WebChatEvent) -> Void) async throws -> ResponseBaseline {
        try await bridge.navigate(to: config.chatURL)
        await bridge.wait(ms: max(config.toolCallDelayMs, 500))
        let preamble = WebToolProtocolEmulator.systemPreamble(
            userSystemPrompt: config.systemPrompt,
            projectRoot: projectRoot,
            directory: projectRoot,
            isGitRepo: (try? GitRepository.repositoryRoot(for: projectRoot)) != nil
        )
        // Recent summary = the last response minus the limit notice; the caller's
        // system prompt / goal carry the durable intent. No fabricated content.
        let recent = WebSessionLimitLogic.limitMarkers.reduce(lastResponse) { acc, marker in
            acc.replacingOccurrences(of: marker, with: "", options: .caseInsensitive)
        }.trimmingCharacters(in: .whitespacesAndNewlines)
        let seed = WebSessionLimitLogic.carryOverSeed(systemPreamble: preamble,
                                                       goal: config.systemPrompt.isEmpty ? nil : config.systemPrompt,
                                                       recentSummary: String(recent.prefix(2000)))
        let baseline = try await sendPossiblyChunked(seed, emit: emit)
        emit(.sessionRestarted)
        return baseline
    }

    /// Restart the web session with an AI-generated summary of the conversation.
    /// The summary is produced by the local free model and focuses on the current
    /// task, tool results, and actionable context — much richer than the raw
    /// `restartSessionWithCarryOver` which only keeps the last 2000 chars.
    /// `pendingMessage` (the turn's unanswered user request) is appended after
    /// the seed so a quota-driven restart does not silently drop the task —
    /// the seed already carries the tool preamble, so the raw request suffices.
    func restartSessionWithSummary(lastResponse: String,
                                           summary: String?,
                                           emit: (WebChatEvent) -> Void,
                                           restartCount: Int = 0,
                                           pendingMessage: String? = nil,
                                           taskGoal: String? = nil) async throws -> ResponseBaseline {
        try await bridge.navigate(to: config.chatURL)
        await bridge.wait(ms: max(config.toolCallDelayMs, 500))
        let preamble = WebToolProtocolEmulator.systemPreamble(
            userSystemPrompt: config.systemPrompt,
            projectRoot: projectRoot,
            directory: projectRoot,
            isGitRepo: (try? GitRepository.repositoryRoot(for: projectRoot)) != nil
        )
        // The goal slot carries the ACTUAL task (the turn's user request),
        // never the system prompt: the preamble already contains it, and
        // duplicating ~2.5KB of instructions is exactly the dumb stuffing
        // the handoff must avoid.
        let goal: String? = {
            let t = (taskGoal ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }()
        let seed: String
        if let summary, !summary.isEmpty {
            seed = WebSessionSummarizer.summarizedSeed(
                systemPreamble: preamble,
                goal: goal,
                summary: summary,
                restartCount: restartCount
            )
        } else {
            // Fallback: no summary available, use raw recent context.
            let recent = WebSessionLimitLogic.limitMarkers.reduce(lastResponse) { acc, marker in
                acc.replacingOccurrences(of: marker, with: "", options: .caseInsensitive)
            }.trimmingCharacters(in: .whitespacesAndNewlines)
            seed = WebSessionLimitLogic.carryOverSeed(
                systemPreamble: preamble,
                goal: goal,
                recentSummary: String(recent.prefix(2000))
            )
        }
        let fullSeed: String
        if let pending = pendingMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
           !pending.isEmpty {
            fullSeed = seed + "\n\n---\n\n" + pending
        } else {
            fullSeed = seed
        }
        let baseline = try await sendPossiblyChunked(fullSeed, emit: emit)
        MyCoderAPIServer.appendLog("🔄 [WebChatDriver] restartSessionWithSummary: seeded \(fullSeed.count) chars (summary=\(summary?.count ?? 0))")
        emit(.sessionRestarted)
        return baseline
    }
}
