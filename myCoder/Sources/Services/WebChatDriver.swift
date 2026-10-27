import Foundation

/// Drives a full agentic loop over a plain web chat, turning a tool-less web
/// model into a coding agent (plan Раздел 12 Блок 2 п.15). Pure orchestration:
/// all browser I/O goes through `BrowserAutomationBridge` and all tool execution
/// through `WebToolExecutor`, so the loop is fully unit-testable with fakes and
/// runs against Playwright MCP + real executors in the app — no stubs.
struct WebChatDriver {
    let bridge: BrowserAutomationBridge
    let executor: WebToolExecutor
    let selectors: WebVendorSelectors
    let config: WebProviderConfig
    let projectRoot: String
    let accessLevel: AccessLevel
    /// Injectable RNG for deterministic anti-ban jitter in tests.
    var randomUnit: () -> Double = { Double.random(in: 0..<1) }
    /// Poll interval and stability window for end-of-generation detection.
    /// Audit 2026-09-08 (Kimi): bursty streams can pause >600 ms between the
    /// first token and the rest — 3 polls finalized on the first word
    /// ("Need") of a longer answer. 5 polls = 1 s of stillness.
    var pollIntervalMs: Int = 200
    var stabilityChecks: Int = 5
    /// Bound for waiting on a present AND enabled send button after typing
    /// (audit 2026-09-09: ChatGPT materializes it late; Qwen enables it
    /// late). Injectable so tests stay instant.
    var sendEnabledTimeoutMs: Int = 15000
    /// When false, model/effort injection is skipped (used in unit tests where
    /// the fake bridge has no real web UI to configure).
    var injectModelAndEffortEnabled: Bool = true
    /// Mailbox for blocking tool approvals: the driver posts a request, the
    /// UI shows an Allow/Deny card, and the driver waits for the verdict.
    /// Nil in unit tests — gated tools are then auto-declined.
    var approvalBox: WebToolApprovalBox?
    /// How long the driver waits for the user to answer an approval card.
    /// Injectable so unit tests stay instant.
    var approvalWaitSeconds: Int = WebChatDriver.defaultApprovalWaitSeconds
    /// Production default: five minutes for the user to answer.
    static let defaultApprovalWaitSeconds = 300
    /// Wait between retries after a TRANSIENT Kimi overload notice.
    static let overloadWaitSeconds = 20

    /// Harness-tax C3: effective iteration ceiling — the configured budget
    /// capped at the 40-turn hard limit (KDD 2026: cuts TIME/HANG tails).
    static func effectiveMaxIterations(configured: Int) -> Int {
        min(configured, IdleLoopDetector.hardIterationCap)
    }

    private struct ResponseBaseline {
        let text: String
        let fingerprint: String
    }

    /// Run one user turn: inject the message, then loop tool-calls until the
    /// model produces a final answer or hits the iteration limit. Emits events
    /// (streaming/toolCall/toolResult/captcha/final) via `emit`.
    func runTurn(userMessage: String, isFirstMessage: Bool, emit: (WebChatEvent) -> Void, skipSend: Bool = false, preSendFingerprint: String? = nil) async {
        print("🔄 [WebChatDriver] runTurn started, skipSend=\(skipSend)")
        // Stability box for vendor-limit detection (audit 2026-09-09): a
        // single poll can catch a transient flash — the limit error throws
        // only after consecutive confirmations.
        let limitStability = LimitStabilityBox()
        // Reference-type counter for session restarts (progressive summarization).
        let restartCount = RestartCountBox()
        // One model-switch attempt per turn: after switching to Быстрый a
        // lingering paywall marker must fail honestly, not re-enter the
        // switch/restart cycle forever.
        var kimiSwitchAttempted = false
        // Set when the turn started directly on the Fast model after a
        // proactive switch: the browser is already on the verified model, so
        // model injection (which would re-select K3 from the stale config)
        // must be skipped.
        var kimiSwitchedAtStart = false
        do {
            try Task.checkCancellation()
            // Audit 2026-09-11: Kimi K3 is persistently overloaded (fullscreen
            // "too many people" dialog on the /agent surface). If the page
            // already shows quota markers with a K3-family model selected,
            // switch to Fast NOW instead of burning a send on K3 first. A
            // single poll suffices here — a false positive only costs a
            // switch to the usable Fast model, and SmartSend-submitted turns
            // are excluded (the message is already in flight).
            if !skipSend,
               config.vendor.id == "kimi",
               WebChatSurfaceLogic.isKimiAgentModel(config.selectedModel, vendor: config.vendor),
               await kimiQuotaImmediatelyVisible() {
                kimiSwitchAttempted = true
                emit(.streaming("Kimi \(config.selectedModel) unavailable — switching to Быстрый…"))
                let switched = await switchToFastModel(emit: emit)
                MyCoderAPIServer.appendLog("🔀 [WebChatDriver] turn-start kimiQuota: switchToFastModel → \(switched)")
                if switched {
                    kimiSwitchedAtStart = true
                } else {
                    emit(.error("Failed to switch Kimi to Быстрый model. Check the subscription or quota."))
                    return
                }
            }
            // Check session state before touching any model/effort controls. A
            // logged-out or captcha page must produce its actionable interruption
            // event rather than a misleading injection failure.
            if let interruption = try await checkInterruptions(emit: emit, limitStability: limitStability) {
                if case .captchaDetected = interruption {
                    emit(interruption)
                    try await waitForCaptchaResolution(emit: emit)
                } else {
                    emit(interruption)
                    print("🔄 [WebChatDriver] runTurn interrupted")
                    return
                }
            }

            // Inject the selected model and effort before sending, so the web
            // UI reflects the user's current selection (plan Раздел 13 п.5).
            // Audit 2026-09-09 (ChatGPT live): when SmartSend already
            // submitted (skipSend), the page is mid-navigation to the new
            // remote chat — opening model/effort menus NOW races and kills
            // the in-flight submit (verified submit, empty home page, dead
            // turn). Injection runs only when THIS driver will type+click
            // itself; a submitted message already went out under the active
            // model and menus cannot retroactively change it.
            // A proactive turn-start switch to Fast already left the browser
            // on the verified model — injecting now would re-select K3 from
            // the stale config copy and undo the switch.
            if injectModelAndEffortEnabled && !skipSend && !kimiSwitchedAtStart {
                let injectionSucceeded = await injectModelAndEffort(emit: emit)
                guard injectionSucceeded else {
                    // Never type/send when the browser did not confirm the
                    // selected model or required effort. The caller may refresh
                    // the live catalog and retry this same local turn safely.
                    print("🔄 [WebChatDriver] runTurn: injection failed")
                    return
                }
            }

            // On the first message of a session, prepend the tool-protocol preamble.
            var message = userMessage
            if isFirstMessage {
                let preamble = WebToolProtocolEmulator.systemPreamble(
                    userSystemPrompt: config.systemPrompt,
                    projectRoot: projectRoot,
                    directory: projectRoot,
                    isGitRepo: (try? GitRepository.repositoryRoot(for: projectRoot)) != nil
                )
                message = preamble + "\n\n---\n\n" + userMessage
            }

            // If skipSend is true, SmartSend already typed and clicked.
            // Just get the baseline response and wait for the answer.
            var responseBaseline: ResponseBaseline
            if skipSend {
                print("🔄 [WebChatDriver] skipSend=true, getting baseline response")
                let baselineText: String
                let baselineFingerprint: String
                if let preSendFingerprint {
                    // Round 30b: the answer may ALREADY be fully rendered by the
                    // time we get here (binding + injection took seconds). Use
                    // the fingerprint captured BEFORE SmartSend submitted so any
                    // post-send content counts as new.
                    baselineText = ""
                    baselineFingerprint = preSendFingerprint
                } else {
                    baselineText = (try? await readLatestResponse()) ?? ""
                    baselineFingerprint = (try? await bridge.responseFingerprint(selector: selectors.responseContainer)) ?? baselineText
                }
                print("🔄 [WebChatDriver] baseline: text_len=\(baselineText.count), fingerprint_len=\(baselineFingerprint.count)")
                responseBaseline = ResponseBaseline(text: baselineText, fingerprint: baselineFingerprint)
            } else {
                print("🔄 [WebChatDriver] skipSend=false, calling sendPossiblyChunked")
                responseBaseline = try await sendPossiblyChunked(message, emit: emit)
            }
            // Reference text for the own-echo guard in awaitResponse: what we
            // actually submitted last (SmartSend submits the raw user text,
            // the driver the preamble-wrapped message, tool turns the results
            // block). Updated after every submit below.
            var lastSentText = skipSend ? userMessage : message

            var iteration = 0
            // Consecutive vendor error placeholders on this turn (audit
            // 2026-09-09): more than one regenerate nudge never helped live
            // — it only burns the iteration budget. Reset on any genuine
            // response below.
            var consecutiveEmptyResponses = 0
            // A model refusal ("tools unavailable", "no context") is re-
            // anchored exactly once per turn; a repeated refusal is accepted
            // honestly instead of looping nudges forever.
            var refusalNudgedThisTurn = false
            // Harness-tax C3: idle-loop state for this turn. Fed with every
            // parsed tool call; trips on the third consecutive identical call.
            var idleDetector = IdleLoopDetector()
            while true {
                try Task.checkCancellation()
                // Guard against session drop / captcha before reading.
                if let interruption = try await checkInterruptions(emit: emit, limitStability: limitStability) {
                    if case .captchaDetected = interruption {
                        emit(interruption)
                        try await waitForCaptchaResolution(emit: emit)
                    } else if case .kimiOverloaded = interruption {
                        // Transient overload (audit 2026-09-11, user evidence:
                        // the "Слишком много людей" fullscreen modal): the
                        // vendor is BUSY, not quota-blocked — dismiss the
                        // modal, WAIT, and retry the SAME session. Bounded
                        // retries; after the last wait the turn fails
                        // honestly instead of looping forever.
                        emit(.streaming("Kimi is overloaded — dismissed the notice, waiting \(WebChatDriver.overloadWaitSeconds)s before retrying…"))
                        await dismissOverloadModal()
                        await bridge.wait(ms: WebChatDriver.overloadWaitSeconds * 1000)
                        MyCoderAPIServer.appendLog("⏳ [WebChatDriver] kimiOverloaded: waited \(WebChatDriver.overloadWaitSeconds)s, retrying")
                        limitStability.consecutive = 0
                        continue
                    } else if case .kimiQuotaExhausted = interruption {
                        // Kimi K3/K3 Swarm quota exhausted: switch to "Быстрый"
                        // model and restart the session. Only once per turn.
                        // The turn's request is re-sent on the fresh session —
                        // the seed alone carries no task.
                        if kimiSwitchAttempted {
                            emit(.error("Kimi quota limit persists after switching to Быстрый. Check the subscription or start a new chat."))
                            return
                        }
                        kimiSwitchAttempted = true
                        emit(.streaming("Kimi \(config.selectedModel) quota exhausted — switching to Быстрый…"))
                        let switched = await switchToFastModel(emit: emit)
                        MyCoderAPIServer.appendLog("🔀 [WebChatDriver] kimiQuota: switchToFastModel → \(switched)")
                        if switched {
                            responseBaseline = try await restartSessionWithSummary(
                                lastResponse: "",
                                summary: nil,
                                emit: emit,
                                restartCount: restartCount.count,
                                pendingMessage: userMessage
                            )
                            lastSentText = userMessage
                            restartCount.count += 1
                            continue
                        }
                        emit(.error("Failed to switch Kimi to Быстрый model. Check the subscription or quota."))
                        return
                    } else {
                        emit(interruption)
                        return
                    }
                }

                let response: String
                do {
                    response = try await awaitResponse(after: responseBaseline,
                                                         emit: emit,
                                                         sentText: lastSentText,
                                                         limitStability: limitStability)
                } catch WebChatError.kimiInterrupted {
                    // A confirmed Kimi limit/overload surfaced mid-wait: route
                    // through the top-of-loop interruption check (switch to
                    // Fast or dismiss-and-wait) instead of killing the turn.
                    // The stability box was reset by the emitter, so the next
                    // check re-confirms from a clean state.
                    limitStability.consecutive = 0
                    continue
                }

                // Web-model session length limit: summarize the conversation
                // using the local free model and restart with compressed context
                // (plan Раздел 12 extension + progressive summarization).
                if WebSessionLimitLogic.isSessionLimitReached(responseText: response) {
                    emit(.sessionLimitReached)
                    // Extract the full conversation from the browser DOM for
                    // summarization — the response text alone is just the last
                    // message, but the summary needs the full context. The
                    // goal is the turn's actual request, not the system prompt.
                    let domTranscript = await extractTranscriptFromDOM()
                    let summary = await WebSessionSummarizer.summarize(
                        transcript: domTranscript,
                        goal: userMessage
                    )
                    if let summary {
                        emit(.streaming("Session limit reached — summarized \(summary.count) chars of context"))
                    }
                    responseBaseline = try await restartSessionWithSummary(
                        lastResponse: response,
                        summary: summary,
                        emit: emit,
                        restartCount: restartCount.count,
                        taskGoal: userMessage
                    )
                    lastSentText = "Previous context summarized:"
                    restartCount.count += 1
                    iteration += 1
                    continue
                }

                // Audit 2026-09-09 (Qwen live): the vendor can render an ERROR
                // PLACEHOLDER instead of an answer (Qwen's
                // div.response-message-empty — "The current content is empty,
                // please regenerate."). That is a failed generation, NOT a
                // final answer: nudge the model ONCE to regenerate; if it
                // keeps failing (live: Qwen failed 10+ times in a row on the
                // same turn) stop with an honest error instead of burning
                // the whole iteration budget on retries.
                if WebVendorErrorPlaceholderLogic.isErrorPlaceholder(response) {
                    if consecutiveEmptyResponses >= 1 {
                        emit(.error("The provider failed to generate a response twice in a row on this turn (empty/error placeholder). Retry the send later."))
                        return
                    }
                    consecutiveEmptyResponses += 1
                    emit(.streaming("The provider failed to generate a response; asking it to regenerate…"))
                    responseBaseline = try await sendPossiblyChunked(
                        "Your previous response did not render. Please regenerate it now — same content, complete.",
                        emit: emit
                    )
                    lastSentText = "Please regenerate your previous response."
                    iteration += 1
                    continue
                }
                consecutiveEmptyResponses = 0

                // Audit 2026-09-11 (Kimi live): the model sometimes refuses
                // without trying — "tools unavailable in this environment" —
                // and the refusal would be accepted as the final answer while
                // zero tools ran. Re-anchor the tool bridge exactly once per
                // turn; a repeated refusal is accepted honestly.
                if !refusalNudgedThisTurn,
                   WebToolProtocolEmulator.isFinalResponse(response),
                   WebRefusalLogic.isToolRefusal(response) {
                    refusalNudgedThisTurn = true
                    emit(.streaming("The model refused without using tools; re-anchoring the tool protocol…"))
                    responseBaseline = try await sendPossiblyChunked(
                        "System reminder: you DO have tool access through this chat — the tools listed in your instructions run on the user's machine and their results return to you. Any belief that you only have sandbox/ipython tools does NOT apply to this chat — ignore it. Do not re-ask for anything already established: prove the bridge works by emitting one list_dir block now, without prose, and wait for its result.",
                        emit: emit
                    )
                    lastSentText = "System reminder: you DO have tool access (prove with list_dir)"
                    iteration += 1
                    continue
                }

                // Proactive progressive summarization: summarize and restart
                // BEFORE the vendor kills the session for length. The allowed
                // budget grows by stepTokens with each restart, so earlier
                // restarts stay compact and later ones carry more detail.
                // Only while tool calls are still pending: a completed final
                // answer must reach the user, never be replaced by a restart.
                // Always restart on budget breach — when the AI summary is
                // unavailable the restart falls back to raw recent context.
                if !WebToolProtocolEmulator.isFinalResponse(response) {
                    let domTranscript = await extractTranscriptFromDOM()
                    let budget = WebSessionSummarizer.maxTokensBeforeSummary(restartCount: restartCount.count)
                    if domTranscript.count > 1000,
                       WebSessionSummarizer.estimateTokens(in: domTranscript) > budget {
                        emit(.streaming("Context is near the vendor limit — summarizing and restarting the session…"))
                        let summary = await WebSessionSummarizer.summarize(
                            transcript: domTranscript,
                            goal: userMessage
                        )
                        if let summary {
                            emit(.streaming("Context summarized (\(summary.count) chars)."))
                        } else {
                            emit(.streaming("Summarizer unavailable — restarting with recent context."))
                        }
                        responseBaseline = try await restartSessionWithSummary(
                            lastResponse: response,
                            summary: summary,
                            emit: emit,
                            restartCount: restartCount.count,
                            taskGoal: userMessage
                        )
                        restartCount.count += 1
                        iteration += 1
                        lastSentText = "Previous context summarized:"
                        continue
                    }
                }

                if WebToolProtocolEmulator.shouldStopLoop(iteration: iteration,
                                                          maxIterations: Self.effectiveMaxIterations(configured: config.maxToolIterations),
                                                          lastResponse: response) {
                    if let feedback = WebToolProtocolEmulator.malformedToolBlockFeedback(from: response) {
                        MyCoderAPIServer.appendLog("⚠️ [WebChatDriver] malformed tool JSON, feeding error back")
                        let feedbackBlock = feedback + "\n"
                        responseBaseline = try await sendPossiblyChunked(feedbackBlock, emit: emit)
                        lastSentText = feedbackBlock
                        iteration += 1
                        continue
                    }
                    if WebToolProtocolEmulator.isFinalResponse(response) {
                        MyCoderAPIServer.appendLog("🏁 [WebChatDriver] final answer: \(response.prefix(120))")
                        emit(.final(response))
                    } else {
                        MyCoderAPIServer.appendLog("🛑 [WebChatDriver] iteration limit reached")
                        emit(.iterationLimitReached)
                    }
                    return
                }

                // Execute each requested tool and feed results back.
                let parsed = WebToolProtocolEmulator.parseToolCallsWithIssues(from: response)
                let calls = parsed.calls
                // Harness-tax C3: stop BEFORE re-executing a call the model
                // already repeated twice — each repeat re-sends the whole
                // context for zero new information.
                for call in calls where call.arguments["__mycoder_truncated"] == nil {
                    if idleDetector.observe(call) {
                        MyCoderAPIServer.appendLog("🛑 [WebChatDriver] idle loop: '\(call.name)' repeated 3x, stopping")
                        emit(.idleLoopStopped(tool: call.name))
                        return
                    }
                }
                var resultsBlock = ""
                // A block the parser could not turn into a call still owes the
                // model an answer: report it as a tool_result error so the turn
                // continues and the model can re-emit a valid call.
                for issue in parsed.issues {
                    let msg = "error: malformed tool call — \(issue.reason). Nothing was executed. Re-emit the COMPLETE call with valid JSON."
                    MyCoderAPIServer.appendLog("⚠️ [WebChatDriver] malformed block for '\(issue.toolName)': \(issue.reason)")
                    resultsBlock += WebToolProtocolEmulator.formatToolResult(name: issue.toolName, result: msg) + "\n"
                    emit(.toolResult(name: issue.toolName, result: msg))
                }
                // Images requested via read_file are attached to the NEXT
                // composer message through the vendor's real upload flow
                // (vision works in every web chat, but only via attachments).
                var pendingImages: [(mime: String, data: Data)] = []
                for call in calls {
                    emit(.toolCall(call))
                    // Audit 2026-09-08 (Qwen live): a stream-truncated call
                    // ("call {"name": "list_dir", "arguments") is NOT executed
                    // — the model must re-emit the complete block, otherwise
                    // garbage arguments run against the project.
                    if call.arguments["__mycoder_truncated"] == "1" {
                        let msg = "Your tool call was cut off mid-JSON before it reached the host. Re-emit the COMPLETE block in the exact taught form (```tool fenced JSON with name and args) and wait for its result."
                        resultsBlock += WebToolProtocolEmulator.formatToolResult(name: call.name, result: msg) + "\n"
                        emit(.toolResult(name: call.name, result: msg))
                        continue
                    }
                    if WebToolAccessGate.permission(for: call, accessLevel: accessLevel) == .requireApproval {
                        // Ask the user and WAIT for the verdict (bounded by
                        // approvalWaitSeconds). Deny/timeout → an honest
                        // tool_result goes back to the model so it can adapt;
                        // the turn is no longer aborted with a dead status line.
                        let request = WebToolApprovalRequest(
                            id: UUID().uuidString,
                            tool: call.name,
                            message: "\(call.name) requires approval (AccessLevel: \(accessLevel.rawValue))"
                        )
                        approvalBox?.post(request)
                        emit(.approvalRequest(request))
                        let approved: Bool
                        if let verdict = approvalBox?.awaitAnswer(timeoutSeconds: approvalWaitSeconds) {
                            approved = verdict
                        } else {
                            approved = false
                        }
                        if approved {
                            // F4: the user verdict travels into the executor —
                            // a plain execute() would re-fire the gate and
                            // block the just-approved call again.
                            let result = await executor.execute(call, userApproved: true)
                            resultsBlock += WebToolProtocolEmulator.formatToolResult(name: call.name, result: result) + "\n"
                            emit(.toolResult(name: call.name, result: result))
                            continue
                        }
                        let msg = "User declined execution of \(call.name) (or the approval timed out). Propose an alternative or continue without this step."
                        resultsBlock += WebToolProtocolEmulator.formatToolResult(name: call.name, result: msg) + "\n"
                        emit(.toolResult(name: call.name, result: msg))
                        continue
                    }
                    if let validationError = WebToolProtocolEmulator.validate(call, projectRoot: projectRoot, accessLevel: accessLevel) {
                        let msg = "validation error: \(validationError)"
                        resultsBlock += WebToolProtocolEmulator.formatToolResult(name: call.name, result: msg) + "\n"
                        emit(.toolResult(name: call.name, result: msg))
                        continue
                    }
                    let result = await executor.execute(call)
                    if let image = (executor as? ProjectWebToolExecutor) != nil
                        ? ProjectWebToolExecutor.parseAttachedImage(from: result)
                        : nil {
                        pendingImages.append((image.mime, image.data))
                        // Never inline megabytes of base64 into the chat text.
                        let summary = "Image \"\(call.arguments["path"] ?? "?")\" is attached to this message; analyze it visually."
                        resultsBlock += WebToolProtocolEmulator.formatToolResult(name: call.name, result: summary) + "\n"
                        emit(.toolResult(name: call.name, result: summary))
                        continue
                    }
                    resultsBlock += WebToolProtocolEmulator.formatToolResult(name: call.name, result: result) + "\n"
                    emit(.toolResult(name: call.name, result: result))
                }

                // Attach every collected image to the composer before the
                // results text goes out, so the vendor's upload handler binds
                // the real bytes to this outgoing message.
                for image in pendingImages {
                    _ = try? await bridge.attachImageToComposer(data: image.data, mime: image.mime)
                    await bridge.wait(ms: 500)
                }

                responseBaseline = try await sendPossiblyChunked(resultsBlock, emit: emit)
                lastSentText = resultsBlock
                iteration += 1
            }
        } catch is CancellationError {
            return
        } catch let error as WebChatError {
            switch error {
            case .captchaResolutionAborted, .sessionLoggedOut:
                return
            default:
                emit(.error(error.localizedDescription))
            }
        } catch {
            emit(.error("\(error)"))
        }
    }

    // MARK: - Steps

    /// Wait for the user to solve a captcha in the same live browser page.
    /// The chat turn remains in the driver; no duplicate prompt or new remote
    /// chat is created. A logout aborts the turn and a bounded timeout avoids a
    /// permanently suspended task.
    private func waitForCaptchaResolution(emit: (WebChatEvent) -> Void) async throws {
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
    private func sendPossiblyChunked(_ text: String, emit: (WebChatEvent) -> Void) async throws -> ResponseBaseline {
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
    private func sendMessage(_ text: String, emit: (WebChatEvent) -> Void) async throws -> ResponseBaseline {
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
    private func composerStillHolds(_ text: String) async -> Bool {
        let probe = String(text.prefix(120))
        let js = """
        (function(){
          var els = document.querySelectorAll(\(WKWebViewBrowserBridge.jsString(selectors.input)));
          var want = \(WKWebViewBrowserBridge.jsString(probe));
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
    private func extractTranscriptFromDOM() async -> String {
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
    private func restartSessionWithCarryOver(lastResponse: String, emit: (WebChatEvent) -> Void) async throws -> ResponseBaseline {
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
    private func restartSessionWithSummary(lastResponse: String,
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

    /// Dismiss a transient Kimi overload modal ("Слишком много людей" with a
    /// Понятно/Understood button) WITHOUT navigating or switching models —
    /// the session stays exactly as it is and the turn retries after a wait.
    private func dismissOverloadModal() async {
        let dismissJS = """
        (function(){
          function isVisible(el) {
            var r = el.getBoundingClientRect();
            var s = window.getComputedStyle(el);
            return r.width > 0 && r.height > 0 && s.display !== 'none' && s.visibility !== 'hidden';
          }
          // Close/X buttons first (language-independent).
          var closeSels = ['[aria-label="Close"]', '[aria-label="Закрыть"]', '[aria-label="关闭"]',
                           '.modal-close', '.dialog-close', 'button[class*="close"]'];
          for (var s = 0; s < closeSels.length; s++) {
            var cands = document.querySelectorAll(closeSels[s]);
            for (var ci = 0; ci < cands.length; ci++) {
              if (isVisible(cands[ci])) { cands[ci].click(); return true; }
            }
          }
          // Dismiss buttons by text (RU/EN/ZH).
          var labels = ['понятно','понял','understood','got it','ok','okay','close','закрыть',
                        '知道了','明白了','好的','确定','关闭'];
          var els = document.querySelectorAll('button, [role="button"]');
          for (var i = 0; i < els.length; i++) {
            if (!isVisible(els[i])) continue;
            var t = ((els[i].innerText || els[i].textContent) || '').trim().toLowerCase();
            if (!t || t.length > 30) continue;
            for (var j = 0; j < labels.length; j++) {
              if (t === labels[j]) { els[i].click(); return true; }
            }
          }
          // Backdrop click, then Escape.
          var masks = document.querySelectorAll('.modal-mask, [class*="backdrop"], [class*="modal-overlay"]');
          for (var k = 0; k < masks.length; k++) {
            if (isVisible(masks[k])) { masks[k].click(); return true; }
          }
          document.dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape', keyCode: 27, bubbles: true}));
          return false;
        })()
        """
        _ = try? await bridge.evaluateJS(dismissJS) as? Bool
    }

    /// Switch Kimi to the "Быстрый" (Fast) model when K3/K3 Swarm quota is
    /// exhausted. Navigates to a fresh Kimi page, dismisses any paywall modal,
    /// and selects the Fast model from the model menu. Returns true if the
    /// switch succeeded.
    private func switchToFastModel(emit: (WebChatEvent) -> Void) async -> Bool {
        // Navigate to a completely fresh Kimi page to clear any modals/state.
        MyCoderAPIServer.appendLog("🔀 [WebChatDriver] switchToFastModel: navigating to fresh kimi.ai")
        try? await bridge.navigate(to: "https://www.kimi.ai/")
        await bridge.wait(ms: 2000)

        // Dismiss any paywall/quota/overload modal that may be blocking the
        // interface (Kimi K3 overload shows a FULLSCREEN dialog, e.g.
        // "Слишком много людей" / "too many people").
        // Strategy: (1) remove modal DOM elements, (2) close/X buttons
        // (language-independent), (3) dismiss buttons by text in RU/EN/ZH,
        // (4) backdrop click, (5) Escape, (6) CSS guard against re-appearance.
        let removeModalJS = """
        (function(){
          var removed = false;
          // Remove known modal containers (Kimi paywall "Слишком много людей", etc.)
          var modals = document.querySelectorAll(
            '[class*="modal"], [class*="Modal"], [class*="paywall"], [class*="Paywall"], ' +
            '[class*="dialog"], [class*="Dialog"], [role="dialog"], [role="alertdialog"]'
          );
          modals.forEach(function(m) {
            // Only remove if it's a blocking overlay (has backdrop or is fixed/fullscreen)
            var style = window.getComputedStyle(m);
            if (style.position === 'fixed' || style.position === 'absolute') {
              m.remove();
              removed = true;
            }
          });
          return removed;
        })()
        """
        _ = try? await bridge.evaluateJS(removeModalJS) as? Bool

        for _ in 0..<8 {
            let dismissModalJS = """
            (function(){
              function isVisible(el) {
                var r = el.getBoundingClientRect();
                var s = window.getComputedStyle(el);
                return r.width > 0 && r.height > 0 && s.display !== 'none' && s.visibility !== 'hidden';
              }
              // 0. Fast path: no visible modal-like overlay at all → nothing to do.
              var ov = document.querySelectorAll(
                '[class*="modal"], [class*="Modal"], [class*="paywall"], [class*="Paywall"], ' +
                '[class*="dialog"], [class*="Dialog"], [role="dialog"], [role="alertdialog"]'
              );
              var anyVisible = false;
              for (var v = 0; v < ov.length; v++) {
                var st = window.getComputedStyle(ov[v]);
                var rr = ov[v].getBoundingClientRect();
                if ((st.position === 'fixed' || st.position === 'absolute' || ov[v].getAttribute('role') === 'dialog' || ov[v].getAttribute('role') === 'alertdialog') &&
                    rr.width > 120 && rr.height > 60 && isVisible(ov[v])) { anyVisible = true; break; }
              }
              if (!anyVisible) return 'none';
              // 1. Close/X buttons first (language-independent).
              var closeSels = [
                '[aria-label="Close"]', '[aria-label="close"]',
                '[aria-label="Закрыть"]', '[aria-label="закрыть"]',
                '[aria-label="关闭"]', '[aria-label="關閉"]',
                '.modal-close', '.dialog-close', '.close-btn', '.close-button',
                '[class*="modal-close"]', '[class*="dialog-close"]',
                'button[class*="close"]', '[class*="btn-close"]'
              ];
              for (var s = 0; s < closeSels.length; s++) {
                var cands = document.querySelectorAll(closeSels[s]);
                for (var ci = 0; ci < cands.length; ci++) {
                  if (isVisible(cands[ci])) { cands[ci].click(); return 'close-btn'; }
                }
              }
              // 2. Dismiss buttons by text: RU / EN / ZH. Exact match first.
              var labels = [
                'понятно', 'понял', 'поняла', 'хорошо', 'ясно',
                'understood', 'got it', 'i see', 'ok', 'okay', 'dismiss', 'close',
                'закрыть', 'пропустить', 'skip', 'no thanks', 'нет, спасибо', 'не надо',
                '知道了', '明白了', '了解', '好的', '确定', '关闭', '知道了!'
              ];
              var els = document.querySelectorAll('button, [role="button"], a, div[class*="btn"], div[class*="button"], span[class*="btn"]');
              for (var i = 0; i < els.length; i++) {
                if (!isVisible(els[i])) continue;
                var t = ((els[i].innerText || els[i].textContent) || '').trim().toLowerCase();
                if (!t || t.length > 30) continue;
                for (var j = 0; j < labels.length; j++) {
                  if (t === labels[j]) { els[i].click(); return 'btn:' + t; }
                }
              }
              // 3. Substring match for short button texts (e.g. "OK, понятно!").
              for (var i2 = 0; i2 < els.length; i2++) {
                if (!isVisible(els[i2])) continue;
                var t2 = ((els[i2].innerText || els[i2].textContent) || '').trim().toLowerCase();
                if (!t2 || t2.length > 14) continue;
                for (var j2 = 0; j2 < labels.length; j2++) {
                  if (t2.indexOf(labels[j2]) !== -1) { els[i2].click(); return 'btn-sub:' + t2; }
                }
              }
              // 4. Backdrop/mask click.
              var masks = document.querySelectorAll(
                '.modal-mask, [class*="modal-mask"], [class*="backdrop"], [class*="Backdrop"], ' +
                '[class*="overlay-mask"], [class*="modal-overlay"]'
              );
              for (var k = 0; k < masks.length; k++) {
                if (isVisible(masks[k])) { masks[k].click(); return 'mask'; }
              }
              // 5. Escape as a last resort.
              document.dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape', keyCode: 27, bubbles: true}));
              document.dispatchEvent(new KeyboardEvent('keyup', {key: 'Escape', keyCode: 27, bubbles: true}));
              return 'esc';
            })()
            """
            if let action = try? await bridge.evaluateJS(dismissModalJS) as? String,
               !action.isEmpty, action != "none" {
                MyCoderAPIServer.appendLog("🔀 [WebChatDriver] switchToFastModel: dismissed modal via \(action)")
                await bridge.wait(ms: 1000)
                // After clicking, re-remove any modal that re-appeared
                _ = try? await bridge.evaluateJS(removeModalJS) as? Bool
            } else {
                break
            }
        }

        // Inject CSS to prevent modals from re-appearing during model switch
        let blockModalsCSS = """
        (function(){
          var style = document.createElement('style');
          style.textContent = '[class*="modal-container"], [class*="ModalContainer"], [class*="paywall-container"], [class*="PaywallContainer"] { display: none !important; }';
          document.head.appendChild(style);
          return true;
        })()
        """
        _ = try? await bridge.evaluateJS(blockModalsCSS) as? Bool
        await bridge.wait(ms: 500)

        // Click the model selector to open the model menu.
        let catalogEntry = try? WebProviderCatalog.loadBundled().selectors(for: config.vendor.id)
        let customSel = config.customModelSelector?.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelButtonSel = catalogEntry?.modelButton ?? (!(customSel ?? "").isEmpty ? customSel : nil)
        if let selectors = modelButtonSel {
            for selector in selectors.split(separator: ",").map({ String($0).trimmingCharacters(in: .whitespacesAndNewlines) }) {
                if (try? await bridge.click(selector: selector)) != nil {
                    await bridge.wait(ms: 600)
                    break
                }
            }
        }

        // Look for the "Быстрый" menu item and click it.
        let fastLabels = ["Быстрый", "Fast", "快速"]
        var verifiedFastLabel: String?
        for label in fastLabels {
            let js = """
            (function(){
              var items = document.querySelectorAll('.model-item, [class*=model-item], [role="menuitem"], [role="option"], li, div');
              for (var i = 0; i < items.length; i++) {
                var t = items[i].textContent || '';
                if (t.indexOf('\(label)') !== -1 && items[i].getBoundingClientRect().width > 0) {
                  items[i].click();
                  return true;
                }
              }
              return false;
            })()
            """
            if let clicked = try? await bridge.evaluateJS(js) as? Bool, clicked {
                await bridge.wait(ms: 1500)
                // Verify the model switched.
                let verifyJS = "(function(){ var el = document.querySelector('.current-model'); return el ? el.textContent.trim() : ''; })()"
                let currentModel = (try? await bridge.evaluateJS(verifyJS) as? String) ?? ""
                MyCoderAPIServer.appendLog("🔀 [WebChatDriver] switchToFastModel: clicked '\(label)', current-model='\(currentModel)'")
                if currentModel.contains("Быстрый") || currentModel.contains("Fast") {
                    verifiedFastLabel = currentModel
                    break
                }
            } else {
                MyCoderAPIServer.appendLog("🔀 [WebChatDriver] switchToFastModel: '\(label)' item not found/clicked")
            }
        }
        guard let fastModel = verifiedFastLabel else {
            MyCoderAPIServer.appendLog("🔀 [WebChatDriver] switchToFastModel: FAILED — no Fast label verified")
            return false
        }
        // Persist the switch so the next turn does not re-inject K3 and hit
        // the same quota wall again. runWebChatTurn re-reads the persisted
        // config via effectiveSelectedModel() before every turn.
        let canonical = config.allModels.first {
            $0 == fastModel || fastModel.contains($0)
        } ?? "Быстрый"
        if config.allModels.contains(canonical) {
            var updated = config
            updated.selectedModel = canonical
            WebProviderStore.save(
                WebProviderStore.upsert(updated, in: WebProviderStore.load())
            )
        }
        return true
    }

    /// Wait until generation finishes: the stop button disappears and the
    /// response text is stable across `stabilityChecks` polls (plan Блок 2 п.24).
    /// `sentText` is the just-submitted user text: while generation was never
    /// observed (no stop control seen this turn), a stable readout that
    /// merely echoes it is our own message rendering — not the answer
    /// (audit 2026-09-08, Kimi). Once generation ran, whatever remains stable
    /// is the answer, even if it quotes the prompt.
    private func awaitResponse(after baseline: ResponseBaseline,
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
    private func recoverRenderedAnswerAfterTimeout(baseline: ResponseBaseline) async throws -> String? {
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
    private func readLatestResponse() async throws -> String {
        let raw = try await readLatestResponseRaw()
        // Audit 2026-09-12 (last chat): vendor code-chrome junk ("tool" chip,
        // "Копировать" copy button) is scraped as standalone lines around
        // fenced blocks. Strip it once here — every consumer (streaming,
        // final answer, tool-call parsing, echo guard) gets clean text, and
        // the tool parser itself is unaffected because chrome lines were
        // never valid JSON anyway.
        return WebScrapedTextSanitizer.sanitizeStreaming(raw)
    }

    private func readLatestResponseRaw() async throws -> String {
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
    private func checkInterruptions(emit: (WebChatEvent) -> Void,
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
    private func kimiQuotaImmediatelyVisible() async -> Bool {
        let url = (try? await bridge.currentURL()) ?? ""
        let pageText = (try? await bridge.pageText()) ?? ""
        let hasInput = (try? await bridge.exists(selector: selectors.input)) ?? true
        return WebSessionLogic.inferState(currentURL: url, hasChatInput: hasInput, pageText: pageText) == .limitReached
    }

    /// Inject the currently selected model and effort into the web UI before
    /// sending a message. Reads the vendor selectors from the catalog; if the
    /// dropdowns are present, clicks them and selects the matching option.
    /// Returns false when a requested model/effort could not be confirmed. The
    /// caller must abort before typing so a recovery retry cannot duplicate text.
    private func injectModelAndEffort(emit: (WebChatEvent) -> Void) async -> Bool {
        // Round 30b: let post-submission navigation settle first.
        await waitForPageURLStability()
        // Resolve vendor-specific selectors from the catalog. A custom provider
        // may have no bundled entry, but can still be safe when the user saved a
        // custom model selector. A selected model without either route is a hard
        // failure: never send under an unverified model.
        let catalogEntry = try? WebProviderCatalog.loadBundled().selectors(for: config.vendor.id)
        var injectionSucceeded = true

        // Model selection requires exact confirmation before sending.
        if !config.selectedModel.isEmpty {
            let configuredModelButton = config.customModelSelector?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? catalogEntry?.modelButton
            let modelSelectors = (configuredModelButton?.split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? [])
                .filter { !$0.isEmpty }
            guard !modelSelectors.isEmpty else {
                injectionSucceeded = false
                emit(.modelInjectionFailed(
                    "No model selector is configured; injection was blocked before send."
                ))
                return false
            }
            // Audit 2026-09-06 (Claude): the model button's own label carries
            // the CURRENT model (e.g. "Sonnet 5 Max" = model Sonnet 5 + Effort
            // Max). When the target model is already active, opening the menu
            // is unnecessary AND the menu may not list the current model in
            // its current state (live evidence: the menu showed only gated
            // families while Sonnet 5 was already selected), which used to
            // fail the send with a false "Model not found".
            // Audit 2026-09-08 (Kimi): the model button packs "Name + effort"
            // ("K3 Swarm / Высокий"), so a substring check treats "K3 Swarm"
            // as "K3" and sends under the wrong model. Kimi exposes the bare
            // model name in `.model-name .name` — compare it EXACTLY. Also, a
            // menu click may navigate to another product surface (live: "K3"
            // landed on /agent*); return to the chat surface and re-verify.
            let activeLabelSelector: String? = {
                switch config.vendor {
                case .kimi: return ".current-model .model-name .name"
                default: return nil
                }
            }()
            let activeIsTarget: Bool = await {
                if let labelSelector = activeLabelSelector,
                   let label = try? await bridge.readText(selector: labelSelector),
                   !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return label.trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                        .lowercased() == config.selectedModel.lowercased()
                }
                if let activeText = (try? await bridge.readText(selector: modelSelectors[0])) {
                    return activeText.trimmingCharacters(in: .whitespacesAndNewlines)
                        .contains(config.selectedModel)
                }
                return false
            }()
            if activeIsTarget {
                await bridge.wait(ms: 200)
            } else {
            var openedSelector: String?
            for selector in modelSelectors {
                guard (try? await bridge.exists(selector: selector)) == true else { continue }
                do {
                    try await bridge.click(selector: selector)
                    openedSelector = selector
                    break
                } catch {
                    continue
                }
            }

            // Audit 2026-09-08 (ChatGPT 2026 UI): free accounts have NO model
            // switcher at all — one automatic model plus the Reasoning pill.
            // Discovery proves this by emitting synthetic "ChatGPT Auto…"
            // labels. When the control is absent from the page AND the
            // selected model is such an auto label, there is nothing to
            // inject; requiring a menu click would block every send on a
            // page that has nothing to click (live: all ChatGPT sends died
            // with "model control is unavailable" although the message had
            // already been submitted and answered). Effort injection below
            // still runs.
            let autoModelBypass = openedSelector == nil && config.vendor == .chatgpt
                && config.selectedModel.lowercased().hasPrefix("chatgpt auto")
            if autoModelBypass {
                await bridge.wait(ms: 200)
            } else if let openedSelector {
                try? await bridge.waitForSelector(selector: "div.model-item, [class*='model-item'], [role='option']", timeout: 5000)
                await bridge.wait(ms: 500)
                let modelText = config.selectedModel
                let itemSelector = catalogEntry?.modelItem ?? "[role='option'], [class*='option']"
                // Round 30b: menus can render late; re-open and re-match within
                // a small bounded budget instead of one-shot failing.
                var clicked = false
                for attempt in 1...SendSubmissionPolicy.maxMatchRetries {
                    if attempt > 1 {
                        try? await bridge.click(selector: openedSelector)
                        await bridge.wait(ms: SendSubmissionPolicy.matchRetryDelayMs)
                        try? await bridge.waitForSelector(selector: "div.model-item, [class*='model-item'], [role='option']", timeout: 5000)
                        await bridge.wait(ms: SendSubmissionPolicy.matchRetryDelayMs)
                    }
                    clicked = (try? await bridge.clickVisibleTextExact(selector: itemSelector, text: modelText)) == true
                    if clicked { break }
                }
                if clicked {
                    // Let the model menu close and the provider commit its state
                    // before touching the independent effort control.
                    await bridge.wait(ms: 800)
                    // Audit 2026-09-08/09 (Kimi): a menu click may navigate to a
                    // different product surface. For agent models (K3/K3 Swarm)
                    // /agent IS the right surface — the choice is verified
                    // there (live: label reads "K3"). Only navigate back when
                    // the surface does NOT match the selected model; a choice
                    // that did not stick is an honest failure, not a silent
                    // send under the wrong model.
                    let afterURL = (try? await bridge.currentURL()) ?? ""
                    if WebChatSurfaceLogic.isProductDetour(afterURL: afterURL,
                                                           chatURL: config.chatURL,
                                                           vendor: config.vendor,
                                                           selectedModel: config.selectedModel) {
                        try? await bridge.navigate(to: WebChatSurfaceLogic.targetSurfaceURL(
                            chatURL: config.chatURL,
                            vendor: config.vendor,
                            selectedModel: config.selectedModel
                        ))
                        try? await bridge.waitForSelector(selector: selectors.input, timeout: 10_000)
                        await bridge.wait(ms: 800)
                        let committed: Bool = await {
                            if let labelSelector = activeLabelSelector,
                               let label = try? await bridge.readText(selector: labelSelector),
                               !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                return label.trimmingCharacters(in: .whitespacesAndNewlines)
                                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                                    .lowercased() == config.selectedModel.lowercased()
                            }
                            return false
                        }()
                        if !committed {
                            injectionSucceeded = false
                            emit(.modelInjectionFailed(
                                "Model '\(modelText)' did not stay selected after returning to the chat page; injection was blocked before send."
                            ))
                        }
                    }
                } else {
                    // Toggle the same control once to avoid leaving a menu overlay
                    // in front of the composer. A visible dropdown without an exact
                    // confirmed option is still a hard failure: never send under a
                    // different model than the one shown in the composer.
                    try? await bridge.click(selector: openedSelector)
                    injectionSucceeded = false
                    emit(.modelInjectionFailed(
                        "Model '\(modelText)' was not found; injection was blocked before send."
                    ))
                }
            } else {
                injectionSucceeded = false
                emit(.modelInjectionFailed(
                    "The page model control is unavailable; model injection was blocked before send."
                ))
            }
            }
        }

        // Effort is optional: models without a live effort selector are not
        // injected. If a requested effort selector exists but cannot confirm the
        // choice, block before typing so recovery cannot duplicate a turn.
        let selectedModel = config.discoveredModels.first(where: { $0.name == config.selectedModel })
        let effortToInject: WebEffort? = {
            // Before any live model profile exists, preserve the legacy
            // persisted-effort path for vendors whose catalog exposes a
            // universal control. Once profiles exist, an undetected model has
            // no verified capability and must not inherit another model's
            // effort setting.
            guard !config.discoveredModels.isEmpty else { return config.effort }
            guard let selectedModel else { return nil }
            return selectedModel.availableEfforts.contains(config.effort) ? config.effort : nil
        }()
        if let candidates = effortToInject.flatMap({ effortCandidates(for: $0) }), !candidates.isEmpty,
           let catalogEntry {
            let selectors = (catalogEntry.effortDropdown?.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) } ?? [])
                .filter { !$0.isEmpty }
            var anySuccess = false
            var foundControl = false
            var lastError = ""
            for selector in selectors {
                do {
                    guard (try? await bridge.exists(selector: selector)) == true else { continue }
                    foundControl = true
                    try await bridge.click(selector: selector)
                    try? await bridge.waitForSelector(selector: "[class*='effort'], [class*='thinking'], [role='option'], [class*='option']", timeout: 5000)
                    await bridge.wait(ms: 500)
                    let itemSelector = catalogEntry.effortItem ?? "[role='option'], [class*='option']"
                    // Round 30b: match ANY known label variant, retrying with a
                    // re-opened menu within the bounded budget.
                    for attempt in 1...SendSubmissionPolicy.maxMatchRetries {
                        if attempt > 1 {
                            try? await bridge.click(selector: selector)
                            await bridge.wait(ms: SendSubmissionPolicy.matchRetryDelayMs)
                        }
                        var labelClicked = false
                        for candidate in candidates where !labelClicked {
                            labelClicked = (try? await bridge.clickVisibleTextExact(selector: itemSelector, text: candidate)) == true
                        }
                        if labelClicked {
                            // Keep effort injection isolated from the model menu.
                            await bridge.wait(ms: 800)
                            anySuccess = true
                            break
                        }
                    }
                    if anySuccess { break }
                    lastError = "effort option not found"
                } catch {
                    lastError = error.localizedDescription
                }
            }
            if foundControl && !anySuccess {
                injectionSucceeded = false
                emit(.effortInjectionFailed(
                    L.t(AppLocalizationKey.locWebEffortNote)
                        .replacingOccurrences(of: "{0}", with: lastError.isEmpty ? "effort option not found; effort injection was blocked before send" : lastError)
                ))
            }
        }

        // Parameters are optional vendor controls. Apply only the user's saved
        // overrides and only when discovery identified matching live controls;
        // absence never blocks a normal send.
        if let model = config.discoveredModels.first(where: { $0.name == config.selectedModel }) {
            await injectParameters(ModelCallParametersStore.parameters(for: config.selectedModel),
                                   profile: model.parameterProfile)
        }
        return injectionSucceeded
    }

    private func injectParameters(_ parameters: ModelCallParameters,
                                  profile: WebModelParameterProfile) async {
        guard parameters.isCustomized, !profile.availableKeys.isEmpty else { return }
        let fragment = ModelCallParametersStore.requestFragment(parameters)
        guard let data = try? JSONSerialization.data(withJSONObject: fragment),
              let json = String(data: data, encoding: .utf8) else { return }
        let script = """
        (function(){
          const values = \(json);
          const visible = el => {
            const s = getComputedStyle(el), r = el.getBoundingClientRect();
            return s.display !== 'none' && s.visibility !== 'hidden' && r.width > 0 && r.height > 0;
          };
          const nodes = Array.from(document.querySelectorAll('input, textarea, select, [role=spinbutton], [role=slider]')).filter(visible);
          const aliases = {
            temperature: /temperature|temp/i,
            max_tokens: /max.?tokens?|max.?output|token.?limit/i,
            top_p: /top.?p/i,
            system: /system.?prompt/i
          };
          let applied = 0;
          Object.keys(values).forEach(key => {
            if (!aliases[key]) return;
            const el = nodes.find(node => {
              const label = ((node.getAttribute('name') || '') + ' ' + (node.getAttribute('aria-label') || '') + ' ' + (node.id || '') + ' ' + (node.innerText || '')).toLowerCase();
              return aliases[key].test(label);
            });
            if (!el) return;
            const value = String(values[key]);
            if (el.tagName.toLowerCase() === 'textarea' || el.tagName.toLowerCase() === 'input') {
              const proto = el.tagName.toLowerCase() === 'textarea' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
              const descriptor = Object.getOwnPropertyDescriptor(proto, 'value');
              if (descriptor && descriptor.set) descriptor.set.call(el, value); else el.value = value;
            } else {
              el.setAttribute('data-mycoder-value', value);
            }
            el.dispatchEvent(new Event('input', {bubbles: true}));
            el.dispatchEvent(new Event('change', {bubbles: true}));
            applied += 1;
          });
          return applied;
        })();
        """
        _ = try? await bridge.evaluateJS(script)
    }

    /// Start a new chat session by clicking the "New Chat" button.
    /// Returns the new chat URL or nil if could not determine.
    func startNewSession() async throws -> String? {
        let catalogEntry = try? WebProviderCatalog.loadBundled().selectors(for: config.vendor.id)

        // Try exact interactive controls only. A fuzzy div click can select a
        // history row or page heading and silently keep the old remote chat.
        let beforeURL = try? await bridge.currentURL()
        let beforeID = try? await getCurrentChatID()
        let newChatTexts = catalogEntry?.newChatTexts ?? ["New Chat", "Новый чат", "New chat", "Начать", "新对话"]
        for text in newChatTexts {
            let clicked = (try? await bridge.clickVisibleTextExact(selector: "button, a, [role='button'], [role='menuitem']", text: text)) ?? false
            guard clicked else { continue }
            await bridge.wait(ms: 2000)
            let afterURL = try await bridge.currentURL()
            let afterID = try? await getCurrentChatID()
            guard afterURL != beforeURL || afterID != beforeID,
                  afterID?.isEmpty == false else { continue }
            return afterURL
        }
        // Fallback: try clicking catalog-specific newChatSelector (e.g. ".new-chat-btn")
        if let newChatSel = catalogEntry?.newChatSelector {
            let clicked = (try? await bridge.click(selector: newChatSel)) != nil
            if clicked {
                await bridge.wait(ms: 2000)
                let afterURL = try await bridge.currentURL()
                let afterID = try? await getCurrentChatID()
                if afterURL != beforeURL || afterID != beforeID {
                    return afterURL
                }
            }
        }
        // Final fallback: try clicking any element with "new-chat" in class
        if (try? await bridge.click(selector: "[class*='new-chat']")) != nil {
            await bridge.wait(ms: 2000)
            let afterURL = try await bridge.currentURL()
            if afterURL != beforeURL {
                return afterURL
            }
        }
        return nil
    }

    /// Extract the chat ID/slug from the current URL or the provider's active
    /// conversation DOM. Kimi can keep the shell at `/` while exposing the
    /// active UUID through data attributes/history links, so URL-only parsing
    /// incorrectly blocked every first send.
    func getCurrentChatID() async throws -> String? {
        let url = try await bridge.currentURL()
        // Kimi/Qwen: /chat/{id}; ChatGPT: /c/{id}.
        let patterns = ["/chat/", "/c/"]
        for pattern in patterns {
            if let range = url.range(of: pattern) {
                let after = url[range.upperBound...]
                let pathPart = after.split(whereSeparator: { $0 == "/" || $0 == "?" || $0 == "#" }).first.map(String.init) ?? String(after)
                if let chatID = WebRemoteChatIdentityLogic.firstValid([pathPart]) {
                    return chatID
                }
            }
        }

        let script = """
        (function(){
          const values = [];
          const selectors = [
            '[data-chat-id]', '[data-conversation-id]', '[data-conversationid]',
            '[data-testid*="conversation" i]', '[aria-current="page"]',
            'a[href*="/chat/"]', 'a[href*="/c/"]'
          ];
          selectors.forEach(selector => document.querySelectorAll(selector).forEach(el => {
            // Audit 2026-09-08 (ChatGPT): `data-testid` VALUES are turn-level
            // keys ("conversation-turn-2", "conversation-options-button"),
            // never the conversation id — reading them bound a turn key as
            // the chat. The selector still FINDS candidate elements; only
            // id-carrying attributes are read.
            ['data-chat-id', 'data-conversation-id', 'data-conversationid', 'href'].forEach(attr => {
              const value = el.getAttribute(attr);
              if (!value) return;
              if (attr === 'href') {
                // Audit 2026-09-08: Kimi sidebar hrefs end with
                // "?chat_enter_method=history" — taking the LAST path segment
                // yielded the query literal ("history") and masked the real
                // id. Emit EVERY path segment and let the validator pick the
                // first id-shaped one (query segments are rejected there).
                const parts = value.split(/[\\/?#]/).filter(Boolean);
                parts.forEach(part => values.push(part));
              } else {
                values.push(value);
              }
            });
          }));
          return JSON.stringify(values);
        })();
        """
        let raw = try await bridge.evaluateJS(script)
        let candidates: [String]
        if let json = raw as? String,
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            candidates = decoded
        } else if let decoded = raw as? [String] {
            candidates = decoded
        } else {
            candidates = []
        }
        return WebRemoteChatIdentityLogic.firstValid(candidates)
    }

    /// Select a model in the web UI.
    func selectModel(_ modelName: String) async throws {
        let selector = try modelSelector()
        // Click model button
        try await bridge.click(selector: selector)
        // Wait for dropdown
        try await bridge.waitForSelector(selector: "div.model-item, [class*='model-item']", timeout: 5000)
        // Find and click matching model
        let clicked = try await bridge.clickVisibleTextExact(
            selector: "div.model-item, [class*='model-item'], [role='option'], [role='menuitem']",
            text: modelName
        )
        if !clicked {
            throw WebChatError.modelNotFound(L.t(AppLocalizationKey.locWebModelNotFound).replacingOccurrences(of: "{0}", with: modelName))
        }
        await bridge.wait(ms: 500)
    }

    /// Select a mode (auto/think/fast/image).
    func selectMode(_ mode: String) async throws {
        switch config.vendor {
        case .qwen:
            try await bridge.click(selector: "[class*='mode-select']")
            try await bridge.waitForSelector(selector: ".ant-select-item-option", timeout: 5000)
            let clicked = try await bridge.clickByText(
                selector: ".ant-select-item-option-content",
                text: mode
            )
            if !clicked { throw WebChatError.modeNotFound(mode) }
        case .kimi:
            // Kimi modes are in sidebar
            let clicked = try await bridge.clickByText(
                selector: "a, button, [role='button']",
                text: mode
            )
            if !clicked { throw WebChatError.modeNotFound(mode) }
        default:
            break
        }
        await bridge.wait(ms: 500)
    }

    /// Select thinking/effort level.
    func selectThinking(_ level: WebEffort) async throws {
        // Round 30b: try live menu labels first, legacy fallbacks after.
        let labels = effortCandidates(for: level) ?? [level.displayName]
        switch config.vendor {
        case .qwen:
            try await bridge.click(selector: ".qwen-thinking-selector .qwen-chat-v2-dropdown-menu-trigger, .qwen-thinking-selector")
            try? await bridge.waitForSelector(selector: ".qwen-chat-v2-dropdown-menu-item, .ant-select-item-option", timeout: 5000)
            var clicked = false
            for label in labels where !clicked {
                clicked = try await bridge.clickByText(
                    selector: ".qwen-chat-v2-dropdown-menu-item, .ant-select-item-option-content",
                    text: label
                )
            }
            if !clicked { throw WebChatError.effortNotFound(labels.first ?? "") }
        case .kimi:
            try await bridge.click(selector: "[class*='effort']")
            try await bridge.waitForSelector(selector: "[class*='effort-option'], [role='option']", timeout: 5000)
            var kimiClicked = false
            for candidate in labels where !kimiClicked {
                kimiClicked = try await bridge.clickByText(
                    selector: "[class*='effort-option'], [role='option']",
                    text: candidate
                )
            }
            if !kimiClicked { throw WebChatError.effortNotFound(labels.first ?? "") }
        default:
            break
        }
        await bridge.wait(ms: 500)
    }

    /// Resolve the model selector for the current vendor.
    private func modelSelector() throws -> String {
        if let custom = config.customModelSelector, !custom.isEmpty { return custom }
        if let catalog = try? WebProviderCatalog.loadBundled().selectors(for: config.vendor.id),
           let button = catalog.modelButton?.trimmingCharacters(in: .whitespacesAndNewlines),
           !button.isEmpty {
            return button
        }
        throw WebChatError.noModelSelector
    }

    /// Map a WebEffort to a vendor-specific label for matching in the dropdown.
    /// Round 30b: right after a verified SmartSend submission the page is still
    /// navigating to its remote chat URL; the model/effort DOM may be mid-reload
    /// and a single immediate injection pass races against it. Wait until the
    /// location has stopped changing before touching vendor menus.
    private func waitForPageURLStability(maxMs: Int = 6000) async {
        var last = (try? await bridge.currentURL()) ?? ""
        var stableReads = 0
        let start = Date()
        while Date().timeIntervalSince(start) * 1000 < Double(maxMs) {
            await bridge.wait(ms: 300)
            let now = (try? await bridge.currentURL()) ?? last
            if now == last {
                stableReads += 1
                if stableReads >= 2 { return }
            } else {
                last = now
                stableReads = 0
            }
        }
    }

    func effortCandidates(for effort: WebEffort) -> [String]? {
        switch config.vendor {
        case .kimi:
            switch effort {
            case .low: return ["快"]
            case .medium: return ["标准"]
            case .high: return ["深度思考"]
            }
        case .qwen:
            // Round 30b: live menu renders English items ("Auto"/"Think"/"Fast");
            // legacy Chinese labels kept as fallbacks for older locales.
            switch effort {
            case .low: return ["Fast", "快"]
            case .medium: return ["Auto", "标准"]
            case .high: return ["Think", "深度思考"]
            }
        case .chatgpt:
            switch effort {
            case .low: return ["low"]
            case .medium: return ["medium"]
            case .high: return ["high"]
            }
        case .claude:
            // Live 2026 Claude UI exposes an Effort submenu inside the model
            // menu ("Effort: Max"); the tiers map to low/medium/high.
            switch effort {
            case .low: return ["Low", "Низкий"]
            case .medium: return ["Medium", "Средний"]
            case .high: return ["Max", "High", "Высокий", "Максимум"]
            }
        case .custom:
            return nil
        }
    }

    private func antiBanDelay() async {
        let ms = WebAntiBanTiming.delayMs(base: config.toolCallDelayMs, randomUnit: randomUnit())
        if ms > 0 { await bridge.wait(ms: ms) }
    }
}

/// Errors that can occur during web chat operations.
enum WebChatError: LocalizedError {
    case modelNotFound(String)
    case modeNotFound(String)
    case effortNotFound(String)
    case modelInjectionFailed(String)
    case effortInjectionFailed(String)
    case selectorNotFound(String)
    case responseTimeout
    case noModelSelector
    case noSession
    case captchaResolutionTimedOut
    case captchaResolutionAborted
    case sessionLoggedOut
    case remoteChatBindingFailed(String)
    case providerLimitReached(String)
    /// Kimi limit/overload surfaced mid-wait: the outer loop re-checks the
    /// page and routes to switch / dismiss-retry — never a fatal error.
    case kimiInterrupted

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let m): return "Model '\(m)' not found in web UI"
        case .modeNotFound(let m): return "Mode '\(m)' not found in web UI"
        case .effortNotFound(let e): return "Effort level '\(e)' not found"
        case .modelInjectionFailed(let message): return message
        case .effortInjectionFailed(let message): return message
        case .selectorNotFound(let selector): return "Browser element was not found: \(selector)"
        case .responseTimeout: return "The browser did not confirm a new response after submit. The message may not have been sent; check the web page/session and retry."
        case .noModelSelector: return "No model selector configured for this vendor"
        case .noSession: return "No active web session"
        case .captchaResolutionTimedOut: return "Captcha was not solved before the browser wait timed out. Retry after completing it."
        case .captchaResolutionAborted: return "Captcha resolution was aborted because the browser session was logged out."
        case .sessionLoggedOut: return "The browser session was logged out."
        case .remoteChatBindingFailed(let message): return message
        case .providerLimitReached(let message): return message
        case .kimiInterrupted: return "Kimi reported a limit while waiting; the turn continues after handling it."
        }
    }
}
