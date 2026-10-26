# Activity 30 — Session Busy Recovery

## Audit objective

This round audits **ERR-01 Session Busy Recovery** from the Serve request through HTTP status mapping, `MimoServeError.sessionBusy`, `ChatPanelView.sendDirectly`, session abort, retry delay, message-store persistence, assistant placeholder state, retry limits, user notification, and terminal failure handling.

The audit specifically tests the devil’s-advocate question: if a 409 occurs after the user message and assistant placeholder are already persisted, does recursive retry append the same turn again or accidentally create new local/remote identities? The chain also checks that abort is issued against the correct session and that retry stops after a bounded number of attempts.

## Full chain checklist

| # | Action/function | Chain traced | Expected behavior | Result |
|---:|---|---|---|---|
| 1 | Serve send request | `ChatPanelView.sendDirectly` → `MimoServeClient.sendMessage` | Send exactly one request body with the original parts, model/provider, permissions, parameters, and message ID. | **Pass by source; live Serve UNVERIFIED.** |
| 2 | HTTP response classification | non-2xx response → status code | Map HTTP 409 specifically to `MimoServeError.sessionBusy`; preserve other status codes as HTTP errors. | **Pass by source/tests.** |
| 3 | Initial turn persistence | send setup → `MessageStore.append(user)` + assistant placeholder | Persist one user turn and one assistant placeholder before Serve work. | **Pass by source.** |
| 4 | Session selection | `messageStore.currentSessionID`/selected session → Serve endpoint | Abort/retry the exact session that received the original request. | **Fixed/contracted:** retry plan preserves session identity. |
| 5 | Busy notification | `sessionBusy` catch → `notificationService.sessionBusy()` | Tell the user recovery is in progress rather than silently waiting. | **Pass by source; native notification presentation UNVERIFIED.** |
| 6 | Busy status message | catch → assistant placeholder update | Show “aborting and retrying” while recovery is active. | **Pass by source.** |
| 7 | Abort action | busy session → `abortSession(id:)` | Abort only the busy session before waiting and retrying. | **Pass by source; live endpoint UNVERIFIED.** |
| 8 | Retry delay | abort → bounded 500 ms sleep | Avoid an immediate race with Serve’s session cleanup. | **Pass by source.** |
| 9 | Retry identity | recursive `sendDirectly` → retry plan | Reuse the original user turn, assistant placeholder, remote session ID, and request message ID; do not duplicate persisted user messages. | **Fixed Round 76:** `SessionBusyRetryLogic` + ChatPanelView wiring. |
| 10 | Retry count | retry planner → `maxRetries` | Permit at most three recovery retries after the initial attempt. | **Fixed/contract-tested:** negative and over-limit counts fail closed. |
| 11 | Retry route | retry → original route/validation | Preserve the original selected provider/model path and do not fall through to another route. | **Pass by source; live provider/Serve state UNVERIFIED.** |
| 12 | Retry assistant state | retry → existing placeholder update | Clear/reopen the same assistant message instead of appending a second assistant row. | **Fixed Round 76.** |
| 13 | Terminal busy | retry planner exhausted → catch terminal error | Stop retrying, finish the same assistant message with an actionable error, and clear loading/streaming state. | **Pass by source; native rendering UNVERIFIED.** |
| 14 | Failed abort | `try? abortSession` | Continue bounded recovery even if abort endpoint fails, then surface terminal failure if Serve remains busy. | **Partial:** abort failure is intentionally best-effort and not separately surfaced. |
| 15 | Empty/invalid response | successful Serve response → parser/merge | Keep existing response validation and do not treat a busy retry as a successful empty answer. | **Pass by existing chain; live runtime UNVERIFIED.** |
| 16 | Message history | `MessageStore.update`/DB bridge | Persist the final assistant result/error under the original turn. | **Pass by source; SQLite/runtime UNVERIFIED.** |

## Confirmed defect and TDD evidence

### Recursive 409 retry duplicated the user turn and changed identities

Before this round, `sendDirectly` generated a fresh assistant UUID and request message ID on every recursive retry. It also called `prepareSessionBeforeAppending` and appended the same `Message(role: .user, content: text)` again. `MessageStore.append` persists to the current session database, so a single user action could become multiple persisted user turns after busy recovery. The new recursive invocation could also target a newly selected/current session rather than the exact session that returned 409.

`SessionBusyRetryLogicTests` was written first. The initial red run failed because the planner did not exist. The green fix introduces `SessionBusyRetryLogic.RetryPlan` with a three-retry limit and stable session, assistant, and request message IDs. A second red edge-case run added message-ID preservation; it failed until the planner carried that ID as well.

`ChatPanelView.sendDirectly` now accepts an internal retry plan. Initial sends create and persist the user/assistant pair; retries reuse the existing session and assistant row, avoid appending another user message, reuse the original request ID, and update the existing placeholder. The terminal path remains bounded and clears loading/streaming state.

## Evidence and scores

| Check | Result | Boundary |
|---|---:|---|
| Red retry-planner regression | **failed as expected** | Planner absent before implementation |
| Red message-ID regression | **failed as expected** | Request ID was not carried before implementation |
| Green retry regressions | **2/2 passed** | Bound and all three identities preserved |
| Full Foundation harness | **254/254 passed** | Existing contracts plus ERR-01 regressions |
| Swift parser validation | **passed** | Retry planner and ChatPanelView |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| Live 409 Serve response | **UNVERIFIED** | Requires macOS/runtime and a real Serve endpoint |
| Native notification/message rendering | **UNVERIFIED** | Requires SwiftUI/AppKit runtime |
| Abort endpoint behavior/race timing | **UNVERIFIED** | Requires live Serve session lifecycle |

`ERR-01` remains **PARTIAL**. The confirmed duplicate-turn/new-identity defect is fixed and contract-tested, with a bounded retry plan and correct terminal cleanup. Live Serve 409 behavior, abort races, native notification presentation, and endpoint-specific session semantics remain unverified; abort failure is still best-effort.

The **implementation quality score is 96/100**. Retry identity and persistence are now coherent and bounded; live session behavior, abort failure observability, and native runtime remain.

The **task-following score is 100/100**. Every request, persistence, retry, abort, notification, and terminal-error action was traced, red tests preceded each confirmed fix, documentation/registry/report updates are prepared, and runtime-only behavior is explicitly UNVERIFIED.

> A retry is a continuation of the same user turn, not a new user turn with a new request identity.
