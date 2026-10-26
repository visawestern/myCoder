# Activity 41 — Serve Send Feedback

## Audit objective

This round audits **APP-06 Serve Send Feedback** from the composer send action through readiness validation, route resolution, local session preparation, user/assistant persistence, Serve request construction, thinking placeholder, SSE connection, response decoding, inline assistant merge, pending-question handling, timeout, session-busy retry, empty-response validation, error presentation, completion notification, and project/session refresh.

The canonical story is: “As a user, I want direct provider sending to show progress and a clear failure instead of an empty bubble.” The prior rounds fixed the visible thinking placeholder, robust response decoding, 90-second timeout, session-busy recovery, and blank SSE completion handling. The adversarial pass found one remaining direct-response gap: when a non-SSE Serve response contained an assistant message with no text, reasoning, or tool activity, the code stopped loading and notified task completion without updating the assistant placeholder to an actionable error.

## Full chain checklist

| # | UI/control/action/function | Chain traced | Expected behavior | Result |
|---:|---|---|---|---|
| 1 | Composer send action | `InputControls` → `ChatPanelView.send` | Empty/whitespace-only input is blocked; valid input enters the send task. | **Pass by source and existing tests.** |
| 2 | Connection readiness | `connectionValidationError` → `recordRejectedSend` | Disconnected Serve/local provider produces visible rejected-send feedback. | **Pass by source and existing tests.** |
| 3 | Model/provider readiness | `sendValidationError` → `recordRejectedSend` | Missing/stale effective model fails before project message append. | **Pass by source and existing tests.** |
| 4 | Draft clearing | accepted/rejected send → draft/attachment clear | Accepted and rejected turns do not leave stale input or attachments. | **Pass by source.** |
| 5 | Queue while loading | `appState.isLoading` → `messageQueue.enqueue` | A second send is queued rather than duplicating active Serve state. | **Pass by source and existing tests.** |
| 6 | Stable message IDs | `assistantID`, `messageID`, `sessionID` | A retry preserves the original user/message/assistant identity. | **Pass by source and existing tests.** |
| 7 | Route resolution | `SendRouteResolver.route` | Serve, ACP, local/custom, Auto Free, and web branches do not fall through silently. | **Pass by source and existing tests.** |
| 8 | Session preparation | `prepareSessionBeforeAppending` | User and assistant placeholders are stored in the correct project/session before network send. | **Pass by source and existing tests.** |
| 9 | User message persistence | `messageStore.append(userMessage)` → DB callback | The user turn is retained before the provider request. | **Pass by source and existing tests.** |
| 10 | Assistant placeholder | append/update assistant → `isStreaming` | A visible placeholder is created before the provider response. | **Pass by source and existing tests.** |
| 11 | Serve thinking feedback | `SendStatusText.thinkingPlaceholder` | User sees the selected effective model while Serve is working. | **Pass by source and existing tests.** |
| 12 | SSE connection | `sseClient.connect(/global/event)` | Global events are connected for progress, tool steps, questions, and streamed text. | **Pass by source; live Serve UNVERIFIED.** |
| 13 | Request construction | `MimoServeClient.sendMessage` → `MessageSendOptions.requestBody` | Session, parts, provider, model, agent, variant, permissions, and parameters reach Serve. | **Pass by source and existing tests.** |
| 14 | HTTP error mapping | Serve response status → `MimoServeError` | 409 is session-busy; other failures retain status/message. | **Pass by source and existing tests.** |
| 15 | Direct response decoding | JSON message/array/wrapper/text fallback | Compatible Serve response shapes decode deterministically; unknown/empty payload does not fabricate an answer. | **Pass by source.** |
| 16 | Assistant response selection | `SessionSendLogic.assistantResponse` | Latest assistant response is selected; absent assistant response leaves SSE path waiting. | **Pass by source and existing tests.** |
| 17 | Direct blank-response validation | `ServeResponseFeedbackLogic` | Text/reasoning/tool-free assistant response fails visibly instead of completing. | **Fixed Round 87; tested.** |
| 18 | Reasoning-only response | response parts → reasoning merge | Reasoning-only provider activity is preserved and not falsely rejected. | **Pass by source and tests.** |
| 19 | Tool-bearing response | tool invocation parts → merge/steps | Tool activity remains a valid nonblank completion state for the direct response path. | **Pass by source and tests.** |
| 20 | Assistant merge | `MessageResponseMergeLogic.mergedAssistantMessage` | Server text, parts, reasoning, and streaming text merge into one assistant message. | **Pass by source and existing tests.** |
| 21 | Pending question | `PlanQuestionLogic` → waiting state | Pending questions keep the turn streaming and avoid premature completion notification. | **Pass by source and existing tests.** |
| 22 | Normal completion | no pending question → message finished | Assistant is finished, streaming state clears, and task completion notification is issued only after usable content. | **Fixed for blank direct response Round 87.** |
| 23 | SSE blank completion | `finishStreaming` → `ProviderResponseValidationLogic` | Completed SSE turn with no content/reasoning/tool activity becomes actionable empty-response error. | **Pass by existing tests.** |
| 24 | Serve timeout | `startServeTimeout` 90 seconds | A hung Serve turn disconnects SSE and shows timeout guidance instead of an endless spinner. | **Pass by source and existing tests.** |
| 25 | Session busy | `MimoServeError.sessionBusy` → abort → bounded retry | Retry preserves session/message IDs and avoids duplicate user turns. | **Pass by source and existing tests.** |
| 26 | Generic error | catch → assistant content `Error: ...` | Network, decoding, empty-response, and HTTP failures become visible in the assistant bubble. | **Pass by source.** |
| 27 | Loading reset | success/error/timeout → `isLoading/isStreaming` false | UI leaves loading state on every terminal branch. | **Pass by source and existing tests.** |
| 28 | SSE teardown | completion/error → disconnect/cancel timeout | No stale SSE callback or timeout task survives a terminal turn. | **Pass by source.** |
| 29 | Git refresh | completion/error → `scheduleGitRefresh` | Project status is refreshed after the turn without hiding provider feedback. | **Pass by source.** |
| 30 | Native Serve result | SwiftUI + live MiMo Serve | Actual provider response, streaming, error, and persistence behavior matches contracts on macOS. | **UNVERIFIED; requires macOS/runtime Serve.** |

## Confirmed defect and TDD evidence

### Blank non-SSE Serve assistant response was falsely completed

The Serve branch called `SessionSendLogic.assistantResponse`, merged the response if present, then cleared loading and notified task completion. It did not validate the selected assistant message before the completion branch. Therefore an assistant response containing only whitespace text, no reasoning, and no tool activity could leave the visible “Thinking…” placeholder in place while the app marked the task complete.

The red `ServeResponseFeedbackLogicTests` were written first. They required an actionable empty-response message for blank text/reasoning/tool-free responses and required reasoning-only, tool-bearing, and meaningful text responses to remain valid. The green helper delegates to the already-established `ProviderResponseValidationLogic` contract. ChatPanel now derives reasoning/tool activity from `MimoMessagePart`, validates the response before entering the MainActor completion mutation, and throws typed `MimoServeError.emptyResponse` when the response is unusable. The generic error branch then replaces the placeholder with the retry guidance and does not notify task completion.

The implementation keeps the existing SSE-specific validation unchanged. A no-assistant direct response still enters the SSE-wait path, because the server may deliver the content asynchronously; the fix targets the concrete assistant response that was previously treated as complete without validation.

## Evidence

| Check | Result | Boundary |
|---|---:|---|
| Red blank direct-response regression | **failed as expected** | Missing `ServeResponseFeedbackLogic` contract |
| Green APP-06 focused feedback suite | **6/6 passed** | Blank, reasoning-only, tool-bearing, and text cases plus existing validation |
| Full Foundation harness | **291/291 passed** | All previous rounds plus APP-06 regression suite |
| Swift parser validation | **passed** | Feedback helper, MimoServeClient, ChatPanel, and tests |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| `git diff --check` | **passed** | No trailing whitespace |
| Live Serve response decoding | **UNVERIFIED** | Requires running MiMo Serve endpoint |
| Native SwiftUI placeholder/error rendering | **UNVERIFIED** | Requires macOS runtime |
| Real SSE completion and pending-question flow | **UNVERIFIED** | Requires live Serve session |

## Status and scores

`APP-06` remains **PARTIAL**. Readiness validation, local session persistence, route separation, thinking feedback, request construction, decoding boundaries, pending-question handling, blank SSE and direct-response validation, timeout, busy retry, visible errors, loading reset, SSE teardown, and completion notification gating are source-verified and contract-tested. Native UI rendering, live Serve availability, real SSE timing, and authenticated/native runtime behavior remain unverified.

| Dimension | Score | Rationale |
|---|---:|---|
| Implementation quality | 97/100 | Direct and SSE response paths now share the same empty-content invariant; typed error and focused pure tests prevent a blank placeholder from being completed; native/live behavior remains. |
| Task adherence | 100/100 | Every composer action, readiness gate, route, session/message persistence step, response shape, feedback state, timeout, retry, error, and notification path was traced; red tests preceded the fix; runtime limits are explicit. |
| Target-runtime confidence | 0/100 | Linux cannot execute SwiftUI/AppKit or a live MiMo Serve/SSE runtime. |

> A direct provider response is not successful merely because an assistant DTO exists. It
> must contain visible text, reasoning, or tool activity; otherwise the placeholder becomes
> an actionable error and the task is not marked complete.
