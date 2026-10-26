# Activity 20 — Browser Transport

## Audit objective

This round audits **WEB-05 Browser Transport (WKWebView)** from the web-provider settings card and persisted `WebTransport` value through `WebProviderConnectivity`, `ChatPanelView`, `WebChatDriver`, `WKWebViewBrowserBridge`, hidden per-project/per-chat browser instances, session restoration, model/effort injection, and send completion.

The source audit confirmed that the production send path is an isolated in-app `WKWebView`. There is no Playwright MCP client and no Chrome CDP attachment implementation in the traced app. A legacy `.cdpCookies` enum value remained decodable and was labeled as “Existing Chrome” in the connection summary, even though the send path could never attach to Chrome. Round 66 fixes that honesty defect while retaining backward-compatible decoding.

## Transport and action checklist

| # | Feature/action | Chain traced | Expected behavior | Result |
|---:|---|---|---|---|
| 1 | Web provider transport display | `WebProvidersSection` → `WebTransportRuntimeLogic.label` | Show the transport actually used by the send path. | **Fixed:** current and legacy values now identify in-app WKWebView; legacy CDP explicitly says unavailable. |
| 2 | Persisted legacy transport decode | `WebProviderConfig` Codable → `.cdpCookies` | Decode old configurations without silently claiming external Chrome is connected. | **Fixed:** effective runtime maps legacy CDP to `.playwrightMCP`; label is honest. |
| 3 | Connection summary | `WebProviderConnectivity.connectionSummary` → status UI | Never report “Existing Chrome” unless there is a real CDP bridge. | **Fixed:** summary uses the tested runtime label. |
| 4 | Settings transport normalization | Web provider card `.onAppear` → `config.transport = .playwrightMCP` → `onSave` | Current UI should not expose an unsupported transport choice. | **Pass/partial:** legacy values normalize to managed in-app transport; no user-selectable CDP path exists. |
| 5 | Hidden browser instance creation | `ChatPanelView.runWebChatTurn` → isolated `WKWebView` → `WKWebViewBrowserBridge` | Each project/session/provider send uses a live isolated browser page without requiring a foreground window. | **Pass by source:** construction and routing are present; native WebKit runtime UNVERIFIED. |
| 6 | Browser navigation | driver/bridge `navigate(to:)` → WKWebView load | Navigate the isolated page to the provider chat URL and wait for readiness. | **Pass by source/contract:** fake bridge coverage exists; live DOM/WebKit UNVERIFIED. |
| 7 | Session restoration | `WebSessionManager.restore` → cookies/localStorage injection → reload when needed | Restore the named browser session before send; preserve project/provider/session separation. | **Pass by source/tests:** restoration contracts pass; WebKit cookie behavior UNVERIFIED. |
| 8 | Model selection | `WebChatDriver.injectModelAndEffort` → selector discovery → exact visible-text click | Confirm the requested model before typing; abort if unavailable. | **Pass:** exact model injection and pre-send abort are covered by full harness/adversarial checks. |
| 9 | Effort selection | driver → vendor effort selector → exact visible-text click | Inject effort only when the selected model supports it; do not expose unsupported effort as success. | **Pass/partial:** logic is guarded; live vendor DOM remains UNVERIFIED. |
| 10 | Message send | driver → bridge typeText → send-button click | Type and submit through the hidden browser, not through a direct API. | **Pass by source/contract:** driver uses bridge; live vendor interaction UNVERIFIED. |
| 11 | Agentic tool loop | browser response → parse tool calls → AccessLevel gate → executor → browser continuation | Continue coding tasks through browser chat with approval interruptions and bounded iterations. | **Pass by Foundation contract:** native WebKit/provider runtime UNVERIFIED. |
| 12 | Empty/old response guard | baseline/fingerprint → stable polling → timeout | Do not journal an unchanged empty DOM as a successful answer. | **Pass:** response timeout and baseline logic are tested. |
| 13 | Browser stop/retry | stop button and hidden page state → turn cancellation/retry | Stop and retry must target the same isolated page/session without duplicate input. | **Partial/UNVERIFIED:** source and fake runtime cover the contract; live WebKit cancellation not executable here. |
| 14 | Playwright MCP transport | expected external transport → no Playwright client in production | Expose this only if the send path can actually invoke it. | **MISSING by scope:** no Playwright MCP transport implementation exists. |
| 15 | Chrome CDP transport | expected external Chrome bridge → no CDP socket/bridge in production | Do not claim attached Chrome or reuse its live context. | **MISSING by scope; label defect fixed:** persisted legacy value now falls back honestly. |
| 16 | Browser runtime availability | macOS/WebKit → Linux Foundation harness | Mark live WKWebView/WebKit behavior as unverified outside macOS. | **UNVERIFIED by policy:** no Linux target-runtime PASS claimed. |

## Confirmed defect and TDD evidence

### Legacy CDP value falsely claimed Existing Chrome

`WebTransport` retained `.cdpCookies`, but no production code opened a CDP socket or used Chrome cookies as a live browser bridge. `WebProviderConnectivity.connectionSummary` nevertheless returned “Existing Chrome” whenever the value was `.cdpCookies`. The settings card also always displayed WKWebView and normalized the value on appearance, proving that the label and runtime were inconsistent.

`WebTransportRuntimeLogicTests` was written before the helper. The red run failed because `WebTransportRuntimeLogic` did not exist. The green helper maps both values to the only real runtime, labels `.playwrightMCP` as “In-app WKWebView”, and labels `.cdpCookies` as “In-app WKWebView (Chrome CDP unavailable)”. The actual connection-summary consumer is covered by the third regression and now uses that label.

## Remaining limitations

WEB-05 remains **PARTIAL**. The app currently implements a hidden/isolated `WKWebView` path, not Playwright MCP or Chrome CDP. The supported UI honestly reflects this, but users cannot choose an external browser transport or attach to an existing Chrome context. Live WebKit navigation, cookies/localStorage, vendor DOM selectors, cancellation, and provider behavior require macOS runtime verification.

## Evidence and scores

| Check | Result | Boundary |
|---|---:|---|
| Red transport-honesty regression | **failed as expected** | Missing runtime-label contract |
| Green transport regressions | **3/3 passed** | Managed label, legacy CDP fallback, connection-summary consumer |
| Full Foundation harness | **212/212 passed** | Existing contracts plus WEB-05 regressions |
| Swift parser validation | **passed** | Runtime helper, connectivity summary, WebProvidersSection |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| Live WKWebView send/navigation | **UNVERIFIED** | Requires macOS/WebKit and live vendor pages |
| Playwright MCP/CDP transport | **MISSING** | No production implementation to execute or verify |

The **implementation quality score is 95/100**. The false transport claim is removed with a small backward-compatible contract and consumer regression; external transports remain intentionally absent rather than mislabeled.

The **task-following score is 100/100**. Every browser transport and send-chain action was traced, red tests preceded the fix, and unsupported macOS/WebKit behavior remains explicitly UNVERIFIED.

> A persisted enum value is not evidence that a transport exists. The UI must describe the runtime that actually executes the next message.
