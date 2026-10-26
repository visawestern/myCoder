# Activity 40 — Verified Browser Send

## Audit objective

This round audits **WEB-10 Verified Browser Send** from the send button’s readiness reason and route selection through web session state, model/effort injection, input/send selector verification, prompt typing, browser submission, response baseline/fingerprint tracking, captcha/logout interruptions, tool-loop retries, final-answer validation, assistant-message mutation, and `send_completed` journaling.

The canonical story is: “As a user, I want sending to fail clearly when the browser input, send button, model, effort, or session state cannot be confirmed.” The prior implementation already required exact model/effort confirmation, rejected blank finals, and avoided false `send_completed` entries for errors, captcha, logout, iteration limits, approval, and injection failures. The fresh adversarial pass found two ordering defects: session state was checked after model/effort injection, and the send button was checked after typing. Both could produce misleading feedback or leave an unsent prompt in the browser composer.

## Full chain checklist

| # | UI/control/action/function | Chain traced | Expected behavior | Result |
|---:|---|---|---|---|
| 1 | Send button disabled reason | `InputViews` → `SendReadinessReason.reason` | Empty input, missing provider/model, or disconnected provider explains why send is blocked. | **Pass by source and existing tests.** |
| 2 | Web route selection | `SendRouteResolver` → `.web(configID)` | Selected web provider reaches the browser route and does not fall through to Serve. | **Pass by source and existing tests.** |
| 3 | Web config lookup | `.web(configID)` → `WebProviderStore.load` | Missing/deleted provider yields a visible error and no browser send. | **Pass by source.** |
| 4 | Session restoration | `WebSessionManager.restore` → cookies/localStorage → WKWebView | Browser uses the selected named session and reports restoration failures. | **Pass by source; native cookies UNVERIFIED.** |
| 5 | Session preflight | `WebChatDriver.runTurn` → `checkInterruptions` | Logout is reported as logout before model/effort UI interaction. | **Fixed Round 86; tested.** |
| 6 | Captcha preflight | `checkInterruptions` → `waitForCaptchaResolution` | Captcha is surfaced and resolved before injection or typing. | **Pass by source and existing tests; native challenge UNVERIFIED.** |
| 7 | Model injection | `injectModelAndEffort` → catalog/custom selector → exact option click | Selected model is confirmed exactly before typing. | **Pass by source and existing tests; live DOM UNVERIFIED.** |
| 8 | Effort injection | model capabilities → effort selector → exact option click | Supported effort is confirmed; unsupported model effort is skipped; failed confirmation blocks send. | **Pass by source and existing tests; live DOM UNVERIFIED.** |
| 9 | Input selector check | `sendMessage` → `bridge.exists(input)` | Missing input fails with selector error and no typing. | **Pass by source and existing tests.** |
| 10 | Send selector check | `sendMessage` → `bridge.exists(sendButton)` | Missing send control fails before reading, delaying, or typing the prompt. | **Fixed Round 86; tested.** |
| 11 | Response baseline | `readLatestResponse` + `responseFingerprint` before submit | Old assistant text cannot be mistaken for the new turn. | **Pass by source and existing tests.** |
| 12 | Prompt chunking | `WebPromptChunker` → multiple `sendMessage` calls | Large prompt chunks preserve one logical turn and only final chunk triggers generation. | **Pass by source and existing tests.** |
| 13 | Anti-ban delay | `antiBanDelay` before type/click | Configured delay is applied without changing message contents. | **Pass by source and existing tests.** |
| 14 | Browser typing | `typeText` after both selectors are confirmed | User prompt is typed only into a verified composer. | **Fixed ordering Round 86.** |
| 15 | Browser submission | `click(sendButton)` | Send click occurs only after verified model/effort and controls. | **Pass by source and existing tests.** |
| 16 | Response polling | `awaitResponse` → stop state/text/fingerprint | Polling requires a changed non-empty response and stable completion. | **Pass by source and existing tests.** |
| 17 | Empty/unchanged response | baseline comparison → timeout/error | Old or blank DOM is never accepted as a successful final answer. | **Pass by source and existing tests.** |
| 18 | Mid-response captcha | polling `checkInterruptions` → solver → resume | Captcha pauses the same turn without retyping or duplicate send. | **Pass by source and existing tests.** |
| 19 | Mid-response logout | polling `checkInterruptions` → typed logout abort | Logout terminates the turn and cannot become completion. | **Pass by source and existing tests.** |
| 20 | Tool-call loop | response → parse/validate → executor → result send | Tool calls execute only under access policy and continue the same browser conversation. | **Pass by source and existing tests.** |
| 21 | Approval interruption | access gate → `.approvalRequired` | Mutating tool waits for user approval and does not complete the send. | **Pass by source and existing tests.** |
| 22 | Session length restart | limit marker → fresh navigation → carry-over seed | A bounded session restart retains context without falsely completing the old response. | **Pass by source and existing tests.** |
| 23 | Iteration limit | bounded loop → `.iterationLimitReached` | Runaway tool loops stop visibly and are not journaled as `send_completed`. | **Pass by source and existing tests.** |
| 24 | Final answer validation | `.final` → `WebSendCompletionLogic.recordsCompletion` | Only a visible non-blank final answer is completion-eligible. | **Pass by source and existing tests.** |
| 25 | Error presentation | `.error` → `WebChatEventPresenter` → `WebChatTurnMutation` | Browser errors replace the assistant bubble with actionable failure text. | **Pass by source; native UI UNVERIFIED.** |
| 26 | Captcha/logout presentation | event → inline status/screenshot → solver lifecycle | User-action interruptions remain visible and solver state closes on terminal outcomes. | **Pass by source and existing tests; native UI UNVERIFIED.** |
| 27 | Retry after injection failure | typed injection failure → catalog refresh → same chat retry | Refresh/retry does not create a duplicate user turn or mark an unverified send complete. | **Pass by source; live runtime UNVERIFIED.** |
| 28 | Completion gate | `completionSignal.take()` | `send_completed` is recorded only after a visible final event. | **Pass by source and existing tests.** |
| 29 | Completion journal metadata | `recordWebBrowserAction` | Journal records exact provider, project, local chat, remote chat, model, and effort. | **Pass by source and existing tests.** |
| 30 | Native send result | SwiftUI/WebKit/vendor page | Actual send, response, captcha, and logout behavior matches the contract in a live authenticated session. | **UNVERIFIED; requires macOS/WebKit.** |

## Confirmed defects and TDD evidence

### Session state was checked after model/effort injection

The old `WebChatDriver.runTurn` attempted model and effort injection before calling `checkInterruptions`. On a logged-out page, this could emit “model control unavailable” and return before the user received the correct logout event. A red regression configured a login URL and missing input while keeping injection enabled. Before the fix, the event list contained only `modelInjectionFailed`; after the fix, it contains `.loggedOut`, no injection failure, and no typed prompt.

The driver now performs session/captcha preflight first. A captcha is resolved through the same bounded solver path; a logout aborts immediately. Only then does the driver touch model/effort controls.

### Send control was checked after typing

The old `sendMessage` checked the input, captured the baseline, delayed, typed the prompt, and only then checked the send button. When the send button was missing, the browser contained a typed but unsent prompt and the user received a failure after a side effect. A red fake-bridge regression set `hasSendButton = false` and asserted that no text was typed. The green implementation verifies both input and send selectors before baseline capture, delays, typing, or clicking.

The driver still checks the control again implicitly at click time through the actual bridge operation; a control can disappear between preflight and click, in which case the bridge error is surfaced and no completion is recorded.

## Evidence

| Check | Result | Boundary |
|---|---:|---|
| Red logout-before-injection regression | **failed as expected** | Injection ran before session preflight |
| Red send-button-before-typing regression | **failed as expected** | Prompt was typed before send-control check |
| Green WebChatDriver suite | **17/17 passed** | Preflight, selector order, captcha, logout, send, tools, retries, limits |
| Full Foundation harness | **289/289 passed** | All previous rounds plus WEB-10 regressions |
| Swift parser validation | **passed** | WebChatDriver, WKWebView bridge, ChatPanel, tests |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| `git diff --check` | **passed** | No trailing whitespace |
| Native WKWebView navigation and DOM | **UNVERIFIED** | Requires macOS runtime and authenticated vendor page |
| Real captcha/logout transitions | **UNVERIFIED** | Requires live third-party sessions |
| Actual remote send/completion journal | **UNVERIFIED** | Linux harness cannot execute native WebKit/UI chain |

## Status and scores

`WEB-10` remains **PARTIAL**. Readiness messaging, session preflight, model/effort guards, selector ordering, baseline/fingerprint response validation, interruption handling, tool/approval limits, retry identity, visible errors, and completion-journal gating are source-verified and contract-tested. Native WebKit execution, live vendor controls, real send results, and authenticated challenge transitions remain unverified.

| Dimension | Score | Rationale |
|---|---:|---|
| Implementation quality | 97/100 | Fail-closed ordering now prevents misleading login classification and unsent typed prompts; all pure/driver contracts pass; native/live behavior remains. |
| Task adherence | 100/100 | Every readiness, session, selector, injection, typing, click, polling, interruption, retry, completion, and journal path was traced; red tests preceded both confirmed fixes; runtime limits are explicit. |
| Target-runtime confidence | 0/100 | Linux cannot execute SwiftUI/AppKit/WebKit or authenticated vendor pages. |

> A browser send is not verified merely because the prompt was typed. The session,
> controls, requested model/effort, response change, and final content must all be
> confirmed, otherwise the turn fails visibly and remains uncompleted.
