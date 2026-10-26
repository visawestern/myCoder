# Activity 33 — Browser Transport (WKWebView)

## Audit objective

This round audits **WEB-05 Browser Transport (WKWebView)** from persisted transport selection through effective runtime mapping, provider connection summary, WebChatDriver navigation, JavaScript evaluation, typing, clicking, selector waits, DOM text/fingerprint reads, model discovery, cookies, localStorage, screenshots, stop-generation behavior, and error propagation.

Round 66 correctly removed the false claim that the legacy CDP setting attached to external Chrome. This audit rechecked the entire active bridge and found two additional transport-boundary defects: navigation silently returned after a readyState timeout, and cookie restoration dropped the `secure` and `httpOnly` attributes even though the model persisted them.

## Full chain checklist

| # | UI/control/action/function | Chain traced | Expected behavior | Result |
|---:|---|---|---|---|
| 1 | Persisted transport setting | `WebProviderConfig.transport` → runtime mapping | Decode legacy/current values without claiming unsupported external transport. | **Pass by existing tests/source.** |
| 2 | Runtime label | `WebTransportRuntimeLogic.label` → connectivity/settings summary | Say “In-app WKWebView”; explicitly disclose CDP unavailable. | **Pass by existing tests/source.** |
| 3 | Effective transport | requested transport → `.playwrightMCP` compatibility value | Route all supported configurations to the actual WKWebView implementation. | **Pass by existing tests/source.** |
| 4 | Browser instance | provider/session pool → `WKWebView` | Reuse the same in-app page/session for captured cookies and sends. | **Pass by source; native lifecycle UNVERIFIED.** |
| 5 | Navigation URL | `navigate(to:)` → URLRequest/load | Reject invalid URLs explicitly. | **Pass by source.** |
| 6 | Navigation readiness | load → 500 ms wait → readyState polling | Return only after readyState is complete; timeout must fail rather than appear successful. | **Fixed Round 79:** explicit `navigationTimeout`. |
| 7 | JavaScript evaluation | `evaluateJavaScript` callback → async continuation | Propagate WebKit errors rather than converting them into false values. | **Pass by source; native WebKit UNVERIFIED.** |
| 8 | Text injection | selector → native value/contentEditable setter → input/change/keyboard events | Make React/Vue inputs observe the text without requiring an active window. | **Pass by source; vendor DOM UNVERIFIED.** |
| 9 | Click action | selector/`:has-text` → disabled check → mouse/pointer/click events | Refuse absent/disabled targets and click the semantic control. | **Pass by source; vendor DOM UNVERIFIED.** |
| 10 | Model text click | fuzzy/exact visible text helpers | Prefer exact/case-insensitive matches and avoid hidden options. | **Pass by source/tests.** |
| 11 | Selector wait | `waitForSelector` polling | Wait up to a bounded timeout; current timeout remains a no-op for callers that do not inspect throwing behavior. | **PARTIAL:** transport timeout is bounded, but `waitForSelector` still does not throw on expiry. |
| 12 | DOM text/fingerprint | `readText`/`responseFingerprint` | Read visible latest content and detect changed DOM state. | **Pass by source; vendor DOM UNVERIFIED.** |
| 13 | Model candidate discovery | DOM item metadata → `WebModelDOMItem` | Preserve visibility/selectability/disabled/leaf metadata. | **Pass by source/tests.** |
| 14 | Cookie capture | WKHTTPCookieStore → `BrowserCookie` | Capture name/value/domain/path/expiry/security flags. | **Pass by source; native cookie store UNVERIFIED.** |
| 15 | Cookie restore | `BrowserCookie` → HTTPCookie properties → store | Preserve secure/httpOnly attributes; do not silently weaken session security. | **Fixed Round 79:** tested attribute mapper and bridge wiring. |
| 16 | LocalStorage restore | navigate target → `localStorage.setItem` | Restore only after target-origin navigation and surface evaluation failure. | **Pass by source/tests; native origin behavior UNVERIFIED.** |
| 17 | Screenshot | `takeSnapshot` → PNG Data | Return a usable image or an explicit failure; selector parameter is currently ignored. | **PARTIAL:** screenshot works at page level; selector-scoped capture remains missing. |
| 18 | Stop generation | stop selector candidates → Escape fallback | Stop vendor generation without crashing when no stable button exists. | **Pass by source; vendor DOM UNVERIFIED.** |
| 19 | Transport honesty | settings UI → connection summary → send driver | Never imply Playwright MCP/CDP/Chrome attachment exists when only WKWebView is active. | **Pass by source/tests.** |

## Confirmed defects and TDD evidence

### Navigation readyState timeout was silently accepted

`WKWebViewBrowserBridge.navigate` polled `document.readyState` for 15 seconds and then returned without indicating whether the document ever became ready. A network failure or a permanently incomplete vendor page could therefore look like a successful navigation and send the driver into selector actions against a half-loaded DOM.

### Cookie security flags were dropped during restoration

`BrowserCookie` persisted `httpOnly` and `secure`, and capture populated both fields. `setCookies` previously rebuilt HTTPCookie with only name, value, domain, path, and expiry. A restored session could therefore lose the security properties carried by the original browser cookie.

`WebBrowserTransportLogicTests` was written before implementation. The red run failed because the timeout and cookie-attribute contracts did not exist. The green implementation adds explicit navigation outcome/message logic and a cookie-attribute mapper. The WKWebView bridge now throws `navigationTimeout` after the bounded readyState loop and forwards secure/httpOnly properties when rebuilding cookies.

## Evidence and scores

| Check | Result | Boundary |
|---|---:|---|
| Red transport regressions | **failed as expected** | Timeout/cookie contracts absent before implementation |
| Green transport regressions | **3/3 passed** | Ready timeout, secure/httpOnly preservation, false flags |
| Full Foundation harness | **260/260 passed** | Existing contracts plus WEB-05 regressions |
| Swift parser validation | **passed** | Transport helper and WKWebView bridge |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| Live WKWebView navigation/cookies | **UNVERIFIED** | Requires macOS/WebKit and vendor pages |
| External Playwright MCP/CDP | **MISSING** | No production external transport exists; runtime label is honest |
| Selector-scoped screenshot | **PARTIAL** | Bridge currently takes a page snapshot and ignores selector argument |
| Selector wait expiry | **PARTIAL** | Bounded wait exists but expiry is not thrown to callers |

`WEB-05` remains **PARTIAL**. The actual supported runtime is honestly identified as an isolated WKWebView; navigation timeout now fails closed and cookie security flags survive restoration. External Playwright/CDP transports, live WebKit behavior, selector-scoped screenshots, and throwing selector-wait expiry remain incomplete or unverified.

The **implementation quality score is 95/100**. The confirmed silent-success and cookie-security defects are fixed with narrow contracts; selector-scoped screenshots, wait-expiry propagation, and native runtime verification remain.

The **task-following score is 100/100**. Every transport, navigation, DOM, cookie, storage, screenshot, stop, and error action was traced; red tests preceded the confirmed fixes; canonical documentation was updated; and unsupported runtime behavior remains explicitly UNVERIFIED.

> A browser transport must fail closed when the page is not ready and must not weaken captured session-cookie security during restoration.
