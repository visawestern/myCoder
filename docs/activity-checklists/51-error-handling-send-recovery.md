# Activity 51 — Error Handling, Send Recovery, and Validation

## Audit objective

This round audits **ERR-01**, **ERR-02**, and **ERR-03** from keyboard/button send through readiness validation, route selection, session creation, Serve transport, 409 recovery, cancellation, SSE finalization, notifications, message persistence, and final user-visible error copy.

## Canonical user stories

| Story | Expected behavior | Round 97 result |
|---|---|---|
| ERR-01 | `sessionBusy` aborts the active session, retries after 500 ms with bounded attempts, and preserves session/assistant/message identities. | **Fixed cancellation gap:** Stop/cancel now prevents abort/sleep/retry from launching another request. Existing bounded retry and identity guarantees remain green. |
| ERR-02 | Route-aware readiness names a known disconnected Serve route while web/local/custom routes remain independent. Transport failure must clear stale Serve connectivity and notify the user. | **Fixed transport gap:** raw Serve URLSession failures map to typed connection failure; only Serve route clears `serverConnected` and emits the disconnect notification. |
| ERR-03 | Effective model validation reports provider/model blockers; truly blank Serve completions fail visibly. | **Fixed empty-array gap:** a Serve response with zero decoded messages now becomes an actionable empty-response error instead of leaving an empty streaming bubble or false completion. |

## Full manual chain checklist

| # | Action/function | Chain and invariant | Result |
|---:|---|---|---|
| 1 | Composer empty state | `EmptyChatStateView` renders `CenteredInputCard`, preserving the same send/stop path as the normal chat panel. | **Pass by source; native SwiftUI runtime UNVERIFIED.** |
| 2 | Send button disabled state | `CenteredInputCard.canSend` and `SendReadinessReason.reason` account for text/attachments, effective model, provider, connection, and loading state. Provider/model reasons are visible; empty-input reason appears after an attempted send. | **Pass by source/tests; native rendering UNVERIFIED.** |
| 3 | Keyboard submit | `CompactChatPromptField.onSubmit` records an attempt, checks `SendButtonActivationLogic`, and invokes the same `onSend` closure as the button. | **Pass by source; native keyboard behavior UNVERIFIED.** |
| 4 | `sendMessage` content guard | `MessageSendValidation.canSend` rejects empty text without attachments while allowing image/file-only turns. | **Pass by existing tests.** |
| 5 | Slash command short-circuit | Slash commands are dispatched before provider transport; local effects do not create remote turns or leak raw commands into models. | **Pass by source/tests.** |
| 6 | Connection readiness | `connectionValidationError` distinguishes MiMo Serve, web, local, custom, and Auto Free routes; known disconnected Serve IDs receive actionable Serve copy. | **Pass by source/tests.** |
| 7 | Model/provider validation | `sendValidationError` uses the effective model fallback and rejects nil, empty, or whitespace provider IDs. | **Pass by source/tests.** |
| 8 | Rejected send persistence | Validation failures preserve the attempted text/files/images in a local session and append a finished assistant error; input/draft/attachments are cleared only after recording. | **Pass by source; native message rendering UNVERIFIED.** |
| 9 | Queue behavior | If another request is loading, a valid turn enters `MessageQueue`; it is not silently discarded. | **Pass by existing source/tests.** |
| 10 | Route resolution | A stable route is resolved before session/placeholder creation; `.none` never falls through into Serve. Direct, web, ACP, Auto Free, and Serve routes remain isolated. | **Pass by source/tests.** |
| 11 | Session identity | Initial send creates/selects one session and one user/assistant turn; retry plan reuses the same session, assistant placeholder, and request message ID. | **Pass by source/tests.** |
| 12 | Serve 409 mapping | MiMo Serve HTTP 409 maps to `MimoServeError.sessionBusy`; other HTTP statuses remain typed HTTP errors. | **Pass by source/tests.** |
| 13 | Busy recovery | On `sessionBusy`, UI reports retrying, emits session-busy notification, aborts the current remote session, waits 500 ms, and retries only while below the explicit bound. | **Pass by source; live 409/abort runtime UNVERIFIED.** |
| 14 | Busy cancellation | `Task.isCancelled` is checked before abort, after abort, and after cancellable sleep; cancelled retry does not call `sendDirectly` again. | **Fixed Round 97 red/green.** |
| 15 | Serve transport | `URLSession` transport failures from `sendMessage` become `MimoServeError.connectionFailed`; ordinary non-transport errors are not incorrectly rewritten. | **Fixed Round 97 red/green/source acceptance.** |
| 16 | Route-scoped disconnect | Only a `.mimoServe` transport failure marks `appState.serverConnected = false` and calls `NotificationService.serverDisconnected`; direct/web/ACP/Auto Free failures remain local. | **Fixed Round 97 red/green/source acceptance.** |
| 17 | Disconnect copy | The assistant bubble receives explicit reconnect guidance rather than generic `Error: ...`; notification copy says the local agent connection was lost. | **Fixed by source; native notification presentation UNVERIFIED.** |
| 18 | SSE setup | Serve sends connect the event stream, register the event handler, and start the 90-second timeout before awaiting the response. | **Pass by source; live SSE runtime UNVERIFIED.** |
| 19 | Non-empty Serve response | Text, reasoning-only, and tool-bearing responses remain valid according to the existing validation contract. | **Pass by existing tests.** |
| 20 | Empty Serve response with DTO | A DTO with no visible text, reasoning, or tool activity throws `MimoServeError.emptyResponse`. | **Pass by existing tests.** |
| 21 | Empty Serve response array | Zero response messages now fails closed with the same actionable empty-response message. | **Fixed Round 97 red/green.** |
| 22 | Final state cleanup | Success, validation failure, disconnect, blank response, stop, and timeout clear loading/streaming/placeholder state consistently; no empty streaming bubble is silently left behind. | **Source fixed; native message lifecycle UNVERIFIED.** |
| 23 | Native boundary | macOS URLSession, WebKit, SSE, AppKit notifications, SwiftUI state rendering, and real MiMo Serve endpoint behavior cannot be executed in the Linux harness. | **UNVERIFIED by policy; not promoted to PASS.** |

## Confirmed defects and TDD evidence

### ERR-01 — cancellation could be defeated by busy recovery

The existing busy path used `try? await Task.sleep(...)` and did not consult cancellation before or after abort/sleep. A user pressing Stop during the 500 ms recovery window could therefore reach another `sendDirectly` call. A red compile regression was written first for cancellation-aware retry planning. `SessionBusyRetryLogic.nextPlan` now accepts cancellation state; `ChatPanelView` guards before abort, after abort, after cancellable sleep, and immediately before retry.

### ERR-02 — raw Serve transport failures were generic and stale

`MimoServeClient.sendMessage` allowed raw `URLSession` transport errors to escape, while `ChatPanelView` rendered only generic error copy and left `serverConnected` unchanged. A route-scoped red regression was written first. Send transport failures now map to `MimoServeError.connectionFailed`; only the Serve route clears stale connection state and emits the existing disconnect notification. Direct, web, ACP, and Auto Free routes are not poisoned by Serve state changes.

### ERR-03 — zero-message Serve response bypassed blank-completion guard

The previous code validated only when `assistantResponse(from:)` returned a DTO. When Serve returned an empty array, finalization could proceed with no visible response and leave an empty streaming placeholder. A red regression was written first for `responseCount == 0`. The feedback helper now fails closed on zero responses while preserving reasoning-only and tool-bearing success cases.

## Evidence

| Check | Result | Boundary |
|---|---:|---|
| ERR-01 cancellation red test | **compile failed as expected → 3/3 passed** | Foundation retry logic |
| ERR-02 transport/disconnect red tests | **compile failed as expected → 3/3 passed** | Foundation classifier + source wiring |
| ERR-03 empty-array red test | **compile failed as expected → passed** | Foundation response validation |
| Persistent Round 97 source acceptance | **passed** | Production wiring |
| Full Foundation harness | **350/350 passed** | Linux-safe suites |
| Adversarial source checks | **12/12 passed** | Existing safety invariants |
| Canonical registry integrity | **274 rows, unique IDs, valid statuses** | Registry acceptance |
| Swift parser validation | **passed** | Changed production/test files |
| `git diff --check` | **passed** | No trailing whitespace |

## Status and scores

The confirmed source-level defects in all three stories are fixed. They remain **PARTIAL** because macOS SwiftUI/AppKit rendering, URLSession behavior against the real local agent, SSE event delivery, native notifications, and live endpoint session semantics are not verifiable in this Linux environment.

| Story | Code quality | Task adherence | Target-runtime confidence |
|---|---:|---:|---:|
| ERR-01 | 99/100 | 100/100 | 0/100 |
| ERR-02 | 99/100 | 100/100 | 0/100 |
| ERR-03 | 99/100 | 100/100 | 0/100 |

> An error path is complete only when it classifies the failure correctly, prevents unsafe continuation, restores state, and tells the user what to do next. Round 97 closes those source-level gaps while preserving the explicit native-runtime boundary.
