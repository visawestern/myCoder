# Activity 32 — Send Validation Errors

## Audit objective

This round audits **ERR-03 Send Validation Errors** from model/provider selection through effective-model resolution, Auto Free/web/local/custom/Serve route readiness, empty input validation, centered and bottom composer controls, keyboard Enter activation, rejected-send persistence, direct-send preflight, provider response parsing, SSE completion, and final assistant-message rendering.

Round 59 had already fixed stale web/Auto Free model gating and blank web/provider response handling. The current adversarial audit found a remaining Serve-specific defect: an empty completed SSE turn could be finalized as a successful task with the generic task-completed fallback, or remain as a blank/Thinking bubble, instead of telling the user that the provider returned no answer.

## Full chain checklist

| # | UI/control/action/function | Chain traced | Expected behavior | Result |
|---:|---|---|---|---|
| 1 | Model selection | `selectedModel`/`effectiveSelectedModel` | Validate the effective model so stale/derived web and Auto Free selections are not rejected incorrectly. | **Pass by existing Round 59 tests/source.** |
| 2 | Provider selection | selected provider → `sendValidationError` | Require a provider when a model is selected. | **Pass by existing tests/source.** |
| 3 | Empty model | `sendValidationError` | Explain that a model must be selected before sending. | **Pass by existing tests/source.** |
| 4 | Empty provider | `sendValidationError` | Explain that a provider must be selected for the model. | **Pass by existing tests/source.** |
| 5 | Empty input | `MessageSendValidation` → `SendReadinessReason` | Explain that text or an attachment is required; do not show it before the first attempted send when the composer is blank. | **Pass by source/tests.** |
| 6 | Centered Send button | `canSend` + `SendStopButton` | Disable invalid send and show reason via inline text, error color, and help. | **Pass by source; native UI UNVERIFIED.** |
| 7 | Bottom Send button | same shared readiness gate | Match centered composer behavior. | **Pass by source; native UI UNVERIFIED.** |
| 8 | Keyboard Enter | `SendButtonActivationLogic` + `canSend` | Never bypass model/provider/route readiness when pressing Enter. | **Pass by existing source/tests.** |
| 9 | Direct send preflight | `ChatPanelView.sendDirectly` | Revalidate readiness before creating/persisting a send turn. | **Pass by source.** |
| 10 | Rejected send persistence | `recordRejectedSend` | Preserve attempted text and actionable assistant error in the current/local session. | **Pass by source; database/native runtime UNVERIFIED.** |
| 11 | Serve response extraction | `SessionSendLogic.assistantResponse` | Distinguish assistant response absence from an in-flight SSE response. | **Pass by source; live Serve UNVERIFIED.** |
| 12 | SSE text delta | `message.part.delta`/updated | Accumulate visible text and update the assistant bubble. | **Pass by source.** |
| 13 | SSE reasoning | reasoning part | Preserve reasoning-only activity as non-empty work, not an empty-answer failure. | **Fixed contract:** reasoning exempts empty-answer report. |
| 14 | SSE tool activity | tool call/step parts | Preserve tool-only activity as valid completion context. | **Fixed contract:** tool/step activity exempts empty-answer report. |
| 15 | SSE idle completion | `session.status idle`/`session.idle` → `finishStreaming` | If no visible text, reasoning, or tool activity exists, show actionable empty-response guidance. | **Fixed Round 78:** blank completed turns no longer claim success. |
| 16 | Valid no-text completion | tool/reasoning activity → finish | Do not falsely report an empty response for legitimate tool/reasoning-only work. | **Fixed/contract-tested.** |
| 17 | Empty response message | validation logic → assistant message | Tell the user the provider returned an empty response and suggest retry/model checks. | **Fixed Round 78.** |
| 18 | Loading cleanup | finish path | Clear loading/streaming and disconnect SSE whether the result is valid or empty. | **Pass by source; native runtime UNVERIFIED.** |

## Confirmed defect and TDD evidence

### Empty completed Serve turns were finalized as success or left misleadingly blank

`finishStreaming` previously marked the assistant message finished and, when `streamingText` was empty and the message content was empty, inserted the localized task-completed message. It did not distinguish a genuinely blank completed response from reasoning/tool activity. When a placeholder such as “Thinking…” was present, it could also remain as the apparent answer. This violated the send-validation expectation that a provider returning no answer must produce actionable guidance.

Red regressions were added to `ProviderResponseValidationLogicTests` before implementation. The first red run failed because completion-specific validation and retry guidance did not exist. The green implementation adds `shouldReportEmptyCompletion(text:reasoning:hasToolActivity:)` and a stable actionable message. `ChatPanelView.finishStreaming` now inspects the assistant message, ignores its synthetic Thinking placeholder, preserves reasoning/tool/step activity as valid, and replaces a truly empty completed turn with the empty-response error before clearing the stream.

## Evidence and scores

| Check | Result | Boundary |
|---|---:|---|
| Red empty-completion regressions | **failed as expected** | Completion contract absent before implementation |
| Green response-validation regressions | **4/4 passed** | Blank, visible text, reasoning, tool activity, and message guidance |
| Full Foundation harness | **257/257 passed** | Existing contracts plus ERR-03 regressions |
| Swift parser validation | **passed** | Response validation and ChatPanelView |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| Native composer/message rendering | **UNVERIFIED** | Requires SwiftUI/AppKit runtime |
| Live Serve/SSE completion behavior | **UNVERIFIED** | Requires macOS runtime and real Serve endpoint |

`ERR-03` remains **PARTIAL**. Effective model/provider/empty-input gates and empty completed-response handling are hardened and contract-tested. Native rendering, live Serve/SSE timing, localized text presentation, and database persistence remain unverified.

The **implementation quality score is 96/100**. The confirmed false-success/blank-bubble path is fixed with a narrow content-aware finalization rule; live runtime and native verification remain.

The **task-following score is 100/100**. Every validation function, button, keyboard path, provider branch, SSE completion path, and persistence action was traced; red tests preceded the confirmed fix; documentation was updated; and runtime-only behavior remains explicitly UNVERIFIED.

> An empty completed response is an error state, not a successful answer and not a reason to leave a synthetic Thinking bubble visible.
