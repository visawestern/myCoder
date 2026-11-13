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
    var preparedSystemPrompt: String? = nil
    /// Production default: five minutes for the user to answer.
    static let defaultApprovalWaitSeconds = 300
    /// Wait between retries after a TRANSIENT Kimi overload notice.
    static let overloadWaitSeconds = 20

    /// Harness-tax C3: effective iteration ceiling — the configured budget
    /// capped at the 40-turn hard limit (KDD 2026: cuts TIME/HANG tails).
    static func effectiveMaxIterations(configured: Int) -> Int {
        min(configured, IdleLoopDetector.hardIterationCap)
    }

    struct ResponseBaseline {
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

            // Every user turn carries the complete instruction. SmartSend uses
            // the identical text and skipSend prevents duplicate submission.
            let preamble = preparedSystemPrompt ?? WebToolProtocolEmulator.systemPreamble(
                userSystemPrompt: config.systemPrompt, projectRoot: projectRoot,
                directory: projectRoot,
                isGitRepo: (try? GitRepository.repositoryRoot(for: projectRoot)) != nil
            )
            let message = TurnDelivery.withSystem(preamble, modelText: userMessage)

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
            // A final answer that announces an action without a tool call gets
            // ONE nudge to actually emit the call (live evidence 2026-11-13).
            var danglingIntentNudgedThisTurn = false
            // Malformed-block feedback already asks the model to re-emit the
            // call; a dangling nudge on top of it would stack corrections.
            var malformedFeedbackSentThisTurn = false
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

                let repairedCalls = await WebToolCallRepairLogic.tryRepair(responseText: response)
                let maxIterations = Self.effectiveMaxIterations(configured: config.maxToolIterations)
                let hasCalls = repairedCalls != nil || !WebToolProtocolEmulator.isFinalResponse(response)
                if iteration >= maxIterations || !hasCalls {
                    if !hasCalls, let feedback = WebToolProtocolEmulator.malformedToolBlockFeedback(from: response) {
                        MyCoderAPIServer.appendLog("⚠️ [WebChatDriver] malformed tool JSON, feeding error back")
                        malformedFeedbackSentThisTurn = true
                        let feedbackBlock = feedback + "\n"
                        responseBaseline = try await sendPossiblyChunked(feedbackBlock, emit: emit)
                        lastSentText = feedbackBlock
                        iteration += 1
                        continue
                    }
                    // Live 2026-11-13: the model ended a turn with "Проверю
                    // счётчики ресурсов в JS." and no tool block, so the plan
                    // never ran. Nudge exactly once, only when one iteration
                    // remains to execute the call. Never at the ceiling and
                    // never after malformed-JSON feedback (that path already
                    // asked for a corrected call).
                    if !danglingIntentNudgedThisTurn,
                       !malformedFeedbackSentThisTurn,
                       iteration + 1 < maxIterations,
                       !hasCalls,
                       DanglingIntentLogic.announcesAction(response) {
                        danglingIntentNudgedThisTurn = true
                        MyCoderAPIServer.appendLog("🔁 [WebChatDriver] dangling intent: announced an action without a tool call")
                        emit(.streaming("The model announced an action without a tool call; asking it to execute it…"))
                        responseBaseline = try await sendPossiblyChunked(
                            DanglingIntentLogic.nudgeMessage,
                            emit: emit
                        )
                        lastSentText = DanglingIntentLogic.nudgeMessage
                        iteration += 1
                        continue
                    }
                    if !hasCalls {
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
                let calls = repairedCalls ?? parsed.calls
                let issues = repairedCalls == nil ? parsed.issues : []
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
                for issue in issues {
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
                    if WebToolAccessGate.permission(for: call, accessLevel: accessLevel, projectRoot: projectRoot) == .requireApproval {
                        // Ask the user and WAIT for the verdict (bounded by
                        // approvalWaitSeconds). Deny/timeout → an honest
                        // tool_result goes back to the model so it can adapt;
                        // the turn is no longer aborted with a dead status line.
                        let request = WebToolApprovalRequest(
                            id: UUID().uuidString,
                            tool: call.name,
                            message: WebToolAccessGate.outOfProjectPath(
                                for: call,
                                projectRoot: projectRoot
                            ).map {
                                OutOfProjectAccessLogic.approvalMessage(
                                    tool: call.name,
                                    path: $0,
                                    projectRoot: projectRoot
                                )
                            } ?? "\(call.name) requires approval (AccessLevel: \(accessLevel.rawValue))"
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
                        let msg = WebToolProtocolEmulator.validationResultText(for: validationError, callName: call.name)
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
