# Activity 21 — Captcha Display and Resume

## Audit objective

This round audits **WEB-07 Captcha Display in Chat** from browser session inference through `WebChatDriver.checkInterruptions`, screenshot capture, `WebChatEventPresenter`, `WebChatTurnMutation`, `ChatPanelView` event handling, the persistent per-project/per-chat `WKWebView`, and the post-captcha send lifecycle.

The original chain correctly detected captcha markers and rendered a PNG in the assistant bubble, but it stopped the driver and finalized the web turn while the actual browser remained a nearly invisible, non-interactive 2-pixel view. The localization note claimed that the agent would resume automatically, although there was no live browser solver surface and no wait/resume loop. Round 67 adds both: an interactive sheet attached to the same WKWebView instance and a bounded driver policy that waits for the page to become connected, resumes the same turn, aborts on logout, and times out honestly.

## Button, action, and function checklist

| # | UI/control/function | Chain traced | Expected behavior | Result |
|---:|---|---|---|---|
| 1 | Captcha marker detection | `WebSessionLogic.detectCaptcha` → `inferState` | Detect reCAPTCHA/hCaptcha/Cloudflare/human-verification markers without classifying ordinary chat text as captcha. | **Pass:** existing detection tests remain green. |
| 2 | Pre-send interruption check | `WebChatDriver.runTurn` → `checkInterruptions` before composer input | Do not type or submit while captcha/login interruption is present. | **Pass:** driver emits interruption before send. |
| 3 | Mid-loop interruption check | driver loop → `checkInterruptions` before response read | Detect captcha after a tool round and pause before further browser actions. | **Fixed:** captcha now enters the bounded resolution wait. |
| 4 | Screenshot capture | `WKWebViewBrowserBridge.screenshot` → `.captchaDetected` | Preserve a visual diagnostic in the chat bubble. | **Pass:** existing screenshot event/presenter tests remain green. |
| 5 | Inline captcha presentation | `.captchaDetected` → `WebChatEventPresenter` → markdown image/status | Explain what happened and show the screenshot in chat. | **Pass:** existing presenter contract remains green. |
| 6 | Live solver sheet | `WebCaptchaPresentationLogic.showSolver` → `captchaSolverContext` → `.sheet` → `WebCaptchaSolverView` → `WebChatWebViewHost` | Open the exact same live WKWebView used by the driver, with hit testing enabled for clicks and typing. | **Implemented by source; native SwiftUI/WebKit runtime UNVERIFIED.** |
| 7 | Captcha user interaction | user clicks/types in the solver sheet | Solve the actual challenge in the authenticated browser page, not in a detached screenshot. | **Implemented by source; live captcha/vendor behavior UNVERIFIED.** |
| 8 | Automatic resume | driver `waitForCaptchaResolution` → `WebSessionLogic.inferState` → `WebCaptchaResolutionLogic.resume` | Resume the existing driver turn after the same page reports connected; never resend the original prompt or create a second remote chat. | **Fixed and policy-tested:** same driver/bridge remains active. |
| 9 | Captcha still present | resolution policy `.wait` | Keep the sheet and driver paused while captcha remains. | **Pass:** pure policy test; live polling runtime UNVERIFIED. |
| 10 | Logout during captcha | resolution policy `.abort` → `.loggedOut` event | Stop safely and tell the user to log in again; do not send stale content. | **Pass by source/test:** native session behavior UNVERIFIED. |
| 11 | Resolution timeout | bounded 600 polls × 500 ms | Avoid an infinite suspended task and surface an actionable retry message. | **Pass by source:** five-minute bound; timing on live WebKit UNVERIFIED. |
| 12 | Terminal event cleanup | presentation `.dismissSolver` and `finishWebTurn` | Dismiss solver on final answer, error, or logout and clear active web state. | **Pass by source:** state contract is explicit; native sheet dismissal UNVERIFIED. |
| 13 | Empty/old screenshot | empty PNG in captcha event | Still show a useful live solver path; do not rely solely on image bytes. | **Pass:** solver action is driven by event, not PNG non-emptiness. |
| 14 | WebKit unavailable | `#if canImport(WebKit)` | Never claim captcha interaction works on Linux; show platform limitation through existing WebKit guard. | **UNVERIFIED by policy:** macOS runtime required. |
| 15 | CAPTCHA iframe/third-party input | live vendor page in WKWebView | Support click/input only if the vendor challenge permits embedded WebKit interaction. | **UNVERIFIED:** third-party challenge behavior cannot be simulated by Foundation harness. |
| 16 | Screenshot-only fallback | chat markdown image | Retain screenshot as diagnosis even when live solver cannot load. | **Pass:** existing presenter path remains intact. |

## Confirmed defects and TDD evidence

### 1. Captcha claimed automatic resume without a resume loop

`WebChatDriver` emitted `.captchaDetected` and returned. `ChatPanelView` then marked the turn finished after no final answer, reset the web session, and provided no way for the driver to observe that the user had solved the challenge. `WebCaptchaResolutionLogicTests` was written first; the red run failed because the policy did not exist. The green policy distinguishes wait, resume, and abort, and `WebChatDriver` now polls the same bridge for up to five minutes.

### 2. Chat showed only a screenshot while the real browser was inaccessible

The chat WKWebView was attached at 2×2 pixels with `allowsHitTesting(false)`. `WebChatEventPresenter` produced an inline markdown image but no interactive bridge. `WebCaptchaPresentationLogicTests` was written first; the red run failed because the presentation policy did not exist. The green implementation opens `WebCaptchaSolverView`, which attaches the exact same `WKWebView` through `WebChatWebViewHost`, allowing the user to click and type in the live page. The screenshot remains in the chat for diagnosis.

## Evidence and scores

| Check | Result | Boundary |
|---|---:|---|
| Red resolution-policy regressions | **failed as expected** | Missing wait/resume/abort contract |
| Green resolution-policy tests | **3/3 passed** | Wait, resume, logout abort |
| Red presentation-policy regressions | **failed as expected** | Missing solver visibility contract |
| Green presentation-policy tests | **3/3 passed** | Show solver, dismiss terminally, ignore progress |
| Existing WebChatDriver + captcha tests | **17/17 passed** | Driver interruption and policy contracts |
| Full Foundation harness | **218/218 passed** | Existing contracts plus WEB-07 tests |
| Swift parser validation | **passed** | Driver, policies, ChatPanel, solver view |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| Native SwiftUI/WebKit interaction | **UNVERIFIED** | Requires macOS runtime and real challenge page |

The **implementation quality score is 91/100**. The previous false automatic-resume behavior is corrected with bounded same-bridge polling and an interactive live solver surface. Native runtime, third-party challenge compatibility, and cancellation while the solver sheet is open still require macOS verification.

The **task-following score is 100/100**. Every captcha function and user action was traced, red regressions preceded both confirmed fixes, screenshot fallback was retained, and macOS/WebKit boundaries remain explicitly UNVERIFIED.

> A screenshot can explain a captcha, but only the same live browser session can solve it and allow the paused agent turn to continue safely.
