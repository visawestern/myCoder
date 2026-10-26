# Activity 52 — Web Transport, Model/Effort Injection, and Captcha UX

## Audit objective

This round audits **WEB-05**, **WEB-06**, and **WEB-07** from provider selection through per-project/per-chat WebKit instance allocation, session-cookie restoration, navigation/readiness, remote-chat UUID binding, model/effort injection, browser send, polling, captcha interruption, captcha solver presentation, completion, retry, and Stop/cancellation.

## Canonical user stories

| Story | Expected behavior | Round 98 result |
|---|---|---|
| WEB-05 | Browser transport is honest and sends through the embedded WKWebView with isolated project/chat sessions. | **Fixed active Stop routing and web cancellation continuation.** Navigation/cookie/session/selector behavior remains source-tested; live WebKit is UNVERIFIED. |
| WEB-06 | Web provider selection uses the valid live/persisted model and effort, injects exact controls before typing, refreshes once after injection failure, and never mixes provider/chat context. | **No new model-selection defect confirmed.** Existing stale-model, exact injection, unsupported-effort, one-shot refresh, and remote-chat binding contracts remain green; native discovery is UNVERIFIED. |
| WEB-07 | Captcha appears in a visible live browser solver, blocks the agent without duplicate sends, resumes the same turn after resolution, and dismisses on terminal/logout states. | **No new captcha-specific defect confirmed.** Existing presentation/resume/abort contracts remain green; native third-party captcha behavior is UNVERIFIED. |

## Full manual chain checklist

| # | Action/function | Chain and invariant | Result |
|---:|---|---|---|
| 1 | Provider selection | Web provider options use `web:<configID>` and selected provider connectivity is independent of Serve/local/custom readiness. | **Pass by source/tests; native SwiftUI menu UNVERIFIED.** |
| 2 | Web model selection | `selectProvider` reconciles the provider’s valid persisted/discovered model; a stale model falls back to a live available model. | **Pass by existing tests.** |
| 3 | Web effort selection | Effort options derive from the selected provider and effective model; unsupported models do not show or inherit another model’s effort. | **Pass by existing tests/source.** |
| 4 | Local session identity | `runWebChatTurn` uses selected workspace/project plus local chat/session identity; each provider/login/project/chat gets a stable browser key. | **Pass by source/tests.** |
| 5 | WebView pool | `webView(for:)` lazily creates up to 100 isolated instances, updates last-used timestamps, and evicts the least-recently-used page at the safety ceiling. | **Pass by source; active-page eviction under live load UNVERIFIED.** |
| 6 | Cookie restore | Saved provider/session cookies and localStorage are restored before navigation; secure/httpOnly flags remain represented; failures append visible status. | **Pass by source/tests; live WKWebView cookie behavior UNVERIFIED.** |
| 7 | Navigation/readiness | Navigation waits for an input selector with a bounded loop; timeout/status is visible instead of silently sending. | **Pass by existing source/tests; live selector behavior UNVERIFIED.** |
| 8 | Remote chat binding | Existing mapping checks provider host and verifies remote UUID after navigation; missing/changed UUID blocks send to prevent context mixing. | **Pass by source; live vendor URL semantics UNVERIFIED.** |
| 9 | Active browser Stop routing | Stop must use the same `projectID`, `chatID`, `providerID`, and active login session key as the send path. | **Fixed Round 98 red/green: prior code used provider-default WebView.** |
| 10 | Web cancellation | Stop cancels Swift task, sends vendor stop action to the active WebView, and prevents the driver/ChatPanel from appending post-stop retry or completion status. | **Fixed Round 98 red/green/source acceptance.** |
| 11 | Browser transport selectors | Vendor catalog selectors drive input/send/response/stop controls; fallback selectors are conservative and missing controls fail before typing. | **Pass by existing tests/source.** |
| 12 | Preflight interruption | Logged-out and captcha states are checked before model/effort injection; logout emits an interruption and does not type. | **Pass by existing tests.** |
| 13 | Captcha detection | Captcha detection captures a screenshot event and blocks until the same live page becomes connected or logs out. | **Pass by existing tests/source.** |
| 14 | Captcha solver UI | Solver sheet contains the live WKWebView, actionable instructions, and interactive dismissal is disabled. | **Pass by source/tests; native sheet behavior UNVERIFIED.** |
| 15 | Captcha resume | Resolution resumes polling/tool loop without creating a second prompt or remote chat. | **Pass by existing tests.** |
| 16 | Captcha abort | Logout or timeout aborts captcha wait and does not send the pending message again. | **Pass by source/tests; live logout/captcha vendor behavior UNVERIFIED.** |
| 17 | Model injection | Exact model control/option is clicked and confirmed before typing; unavailable or unconfirmed model emits a typed failure and blocks send. | **Pass by existing tests/source.** |
| 18 | Effort injection | Effort is injected only when the selected model profile supports it and a live effort control exists; missing effort support does not block a valid send. | **Pass by existing tests/source.** |
| 19 | Parameter injection | Customized call parameters apply only to discovered profile-supported controls and never block normal sends when controls are absent. | **Pass by source; live DOM control behavior UNVERIFIED.** |
| 20 | One-shot catalog retry | Typed model/effort injection failure refreshes the live catalog once and retries the same local turn/remote chat without duplicate user or assistant bubbles. | **Pass by existing source/tests; live WebKit runtime UNVERIFIED.** |
| 21 | Prompt transport | First mapped turn prepends the tool protocol/system prompt; later turns continue the same verified remote chat; large prompts split safely. | **Pass by source/tests.** |
| 22 | Agent loop | Tool calls are validated against access level/project root, executed through the bridge executor, and results are sent back until final/limit/approval. | **Pass by existing tests; live browser model behavior UNVERIFIED.** |
| 23 | Response polling | New DOM response is distinguished from baseline, waits for stop control/stability, emits streaming updates, and times out rather than accepting stale text. | **Pass by existing tests; live DOM timing UNVERIFIED.** |
| 24 | Completion/error cleanup | Final/error/approval/logout/captcha/Stop states update the assistant bubble and release loading/active web state without silently claiming success. | **Pass by source/tests; native SwiftUI state rendering UNVERIFIED.** |

## Confirmed defects and TDD evidence

### WEB-05 — Stop addressed a different WebView

`ChatPanelView` stored the active project/chat web identity, but `MyCoderApp.stopWebGeneration(providerID:)` called `webView(for: config)` without project or chat IDs. The browser stop command could therefore target the provider-default page while the active project/chat page continued generating. A red Foundation test was written first for active identity preservation, followed by persistent source acceptance. `stopWebGeneration` now receives `projectID` and `chatID`, and the ChatPanel passes the active web chat identity.

### WEB-05/WEB-07 — Stop could be followed by web post-driver continuation

The web driver did not observe `Task` cancellation, and `runWebChatTurn` continued into catalog refresh/completion status after the driver returned. A red cancellation regression was written first. `WebChatDriver` now checks cancellation at entry, polling, captcha waits, and loop iterations, exits silently on `CancellationError`, and ChatPanel guards after both the original and refresh driver turns.

### WEB-06 — no new defect after adversarial trace

The existing implementation correctly reconciles stale models, keeps model and effort selectors separate, gates unsupported effort, blocks unconfirmed injection before typing, refreshes once, and reuses verified remote chat identity. No speculative change was made.

### WEB-07 — no new defect after adversarial trace

The existing implementation presents the same live WKWebView in a non-dismissible solver sheet, pauses/resumes on captcha, aborts on logout/timeout, and dismisses on terminal states. No speculative change was made; third-party challenge behavior remains native-unverified.

## Evidence

| Check | Result | Boundary |
|---|---:|---|
| WEB-05 active stop identity red test | **compile failed as expected → 2/2 passed** | Foundation key routing |
| WEB-05/WEB-07 cancellation red test | **compile failed as expected → 1/1 passed** | Foundation cancellation policy |
| Stop-routing source acceptance | **passed** | AppState + ChatPanel wiring |
| Cancellation source acceptance | **passed** | WebChatDriver + ChatPanel wiring |
| Existing web driver/model/effort/captcha suites | **passed** | Foundation browser orchestration |
| Full Foundation harness | **353/353 passed** | Linux-safe suites |
| Adversarial source checks | **12/12 passed** | Existing safety invariants |
| Canonical registry integrity | **274 rows, unique IDs, valid statuses** | Registry acceptance |
| Swift parser validation | **passed** | Changed production/test files |
| `git diff --check` | **passed** | No trailing whitespace |

## Status and scores

WEB-05 has two confirmed source-level defects fixed in Round 98. WEB-06 and WEB-07 received a full chain re-audit with no additional confirmed defect. All three remain **PARTIAL** because native SwiftUI/WebKit rendering, live vendor selectors, cookie restoration, third-party captcha behavior, real browser Stop action, and external model discovery cannot be verified in this Linux environment.

| Story | Code quality | Task adherence | Target-runtime confidence |
|---|---:|---:|---:|
| WEB-05 | 99/100 | 100/100 | 0/100 |
| WEB-06 | 99/100 | 100/100 | 0/100 |
| WEB-07 | 99/100 | 100/100 | 0/100 |

> The browser audit distinguishes “the app owns a WKWebView” from “the stop, send, captcha, and model actions target the exact active project/chat/session page.” Round 98 closes that identity and cancellation gap without claiming live WebKit proof.
