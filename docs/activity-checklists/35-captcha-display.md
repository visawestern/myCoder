# Activity 35 — Captcha Display in Chat

## Audit objective

This round audits **WEB-07 Captcha Display in Chat** from browser-page state inference through captcha screenshot capture, chat event presentation, same-session solver view, interactive input, bounded wait/resume, logout/timeout abort, response polling, final answer delivery, and solver-sheet cleanup.

Round 67 had already replaced the misleading screenshot-only/automatic-resume claim with an interactive solver backed by the exact same live WKWebView. The fresh audit found two additional lifecycle defects: a captcha appearing after submit during response polling was not checked until the response timed out, and the solver visibility policy did not dismiss on all terminal driver outcomes.

## Full chain checklist

| # | UI/control/action/function | Chain traced | Expected behavior | Result |
|---:|---|---|---|---|
| 1 | Page state detection | `WebSessionLogic.detectCaptcha/inferState` | Captcha markers and challenge URLs outrank ordinary connected state. | **Pass by existing tests/source.** |
| 2 | Pre-send interruption | `runTurn` → `checkInterruptions` | Do not type/send while captcha or logout is already visible. | **Pass by existing tests/source.** |
| 3 | Screenshot capture | `bridge.screenshot(selector:nil)` → `captchaDetected` | Provide a diagnostic screenshot without treating it as a solved challenge. | **Pass by source/tests; native WebKit UNVERIFIED.** |
| 4 | Chat presentation | `WebChatEventPresenter` → `WebChatTurnMutation` | Keep captcha note/image visible in the assistant bubble. | **Pass by existing tests/source.** |
| 5 | Solver visibility | `WebCaptchaPresentationLogic` → `WebCaptchaSolverView` | Open the solver only for captcha, using the live browser page. | **Pass by existing tests/source; native sheet UNVERIFIED.** |
| 6 | Same browser session | `WebCaptchaSolverContext.webView` → `WebChatWebViewHost` | Solver input must modify the exact WKWebView used by WebChatDriver, not a screenshot or second login. | **Pass by source; native runtime UNVERIFIED.** |
| 7 | User instruction | solver note/instructions | Explain that the challenge is live and that the agent waits for resolution. | **Pass by source; localization/native rendering UNVERIFIED.** |
| 8 | Pre-send resume | `waitForCaptchaResolution` → `WebCaptchaResolutionLogic` | Connected state resumes the original turn without creating a duplicate prompt/chat. | **Pass by existing tests/source.** |
| 9 | Mid-response detection | `awaitResponse` polling → `checkInterruptions` | Captcha appearing after submit must open the solver before the response timeout. | **Fixed Round 81:** every response poll checks for captcha/logout. |
| 10 | Mid-response resume | same baseline → wait → response polling | After solving, continue reading the original response; do not retype or click Send again. | **Fixed Round 81 and behavior-tested.** |
| 11 | Logout abort | session state → `.loggedOut` → typed abort | Emit one terminal logout event and stop the turn without treating logout as a model response. | **Fixed/contract-tested.** |
| 12 | Bounded wait | 600 × 500 ms polling | Never suspend indefinitely; timeout becomes actionable error. | **Pass by source; five-minute native wait UNVERIFIED.** |
| 13 | Terminal timeout | timeout error → presenter/chat | Timeout is visible and the solver does not remain active forever. | **Pass by source; native presentation UNVERIFIED.** |
| 14 | Final response | `.final` → dismiss solver | A successfully completed turn closes the solver surface. | **Pass by existing tests/source.** |
| 15 | Error response | `.error` → dismiss solver | Fatal browser/provider errors close the solver surface and remain visible in chat. | **Pass by existing tests/source.** |
| 16 | Iteration limit | `.iterationLimitReached` → dismiss solver | Driver stop must close a solver opened for the same turn. | **Fixed Round 81.** |
| 17 | Approval interruption | `.approvalRequired` → dismiss solver | A stopped turn requiring approval must not leave captcha UI blocking the next action. | **Fixed Round 81.** |
| 18 | Injection failure | `.modelInjectionFailed/.effortInjectionFailed` → dismiss solver | Pre-send terminal failure must close solver visibility and show status. | **Fixed Round 81.** |
| 19 | Progress events | streaming/tool/session restart | Non-terminal progress must not dismiss or reopen the solver incorrectly. | **Pass by existing tests/source.** |
| 20 | Vendor/iframe behavior | WKWebView page → challenge provider | Embedded challenge must accept clicks/input and preserve cookies/session. | **UNVERIFIED:** requires macOS/WebKit and real vendors. |

## Confirmed defects and TDD evidence

### Captcha appearing during response polling was missed

`WebChatDriver` checked interruptions before the initial send and before reading each new loop response, but `awaitResponse` itself could poll for up to two minutes without checking page state. A captcha that appeared after submit could therefore produce only `responseTimeout`; the solver never opened and the original turn could not resume.

A red behavioral regression was added to `WebChatDriverTests` with a scripted bridge that changes to a captcha only inside the response-polling phase. Before implementation, the test emitted only `responseTimeout` and no captcha/final event. The green driver now calls `checkInterruptions` at the start of every response poll, waits through `WebCaptchaResolutionLogic` on the same bridge, and resumes the existing baseline without retyping or clicking Send. Logout and captcha timeout now use typed errors so terminal events are not duplicated or misclassified.

### Solver visibility did not dismiss on all terminal outcomes

`WebCaptchaPresentationLogic` dismissed only on final, generic error, or logout. Iteration-limit, approval-required, and model/effort-injection-failure events stop the driver too, but previously returned `.none`, allowing an already-open solver surface to remain visible after the turn had terminated.

Red presentation regressions were added before implementation. They failed for all four omitted terminal outcomes. The green policy dismisses for every driver outcome that terminates the active turn while preserving `.none` for ordinary streaming/tool progress and session restart events.

## Evidence and scores

| Check | Result | Boundary |
|---|---:|---|
| Red mid-response captcha regression | **failed as expected** | Current driver returned response timeout without captcha event |
| Green focused driver/presentation suites | **19/19 passed** | Mid-response resume, pre-send interruption, terminal cleanup |
| Full Foundation harness | **263/263 passed** | Existing contracts plus WEB-07 regressions |
| Swift parser validation | **passed** | WebChatDriver and captcha presentation logic |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| Native SwiftUI/WebKit interaction | **UNVERIFIED** | Requires macOS runtime and real challenge page |
| Third-party iframe compatibility | **UNVERIFIED** | Depends on vendor/WebKit challenge behavior |

`WEB-07` remains **PARTIAL**. Detection, screenshot/event presentation, same-WKWebView interaction, bounded resolution, mid-response resume, typed abort, and terminal solver cleanup are contract-tested. Real vendor captcha pages, iframe permissions, cookies, native sheet interaction, and external challenge compatibility remain unverified.

The **implementation quality score is 94/100**. The missing mid-response interruption and terminal visibility defects are fixed with bounded, identity-preserving logic; native WebKit and third-party compatibility remain.

The **task-following score is 100/100**. Every captcha function, UI event, browser action, polling branch, timeout, logout, resume, and terminal state was traced; red tests preceded both confirmed fixes; canonical documentation was updated; and macOS/WebKit boundaries remain explicitly UNVERIFIED.

> A captcha can appear after submit, not only before it; the live solver must open at the point of interruption and resume the original browser turn without sending the prompt twice.
