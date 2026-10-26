# Activity 22 — Web Providers in Chat Input

## Audit objective

This round audits **WEB-06 Web Providers in Chat Input** from persisted `WebProviderConfig` and captured session cookies through `WebProviderConnectivity`, `MyCoderApp.providerOptions`, model/effort selection, `effectiveSelectedModel`, `modelsForSelectedProvider`, Web Providers settings actions, and the final `SendRouteResolver`/`WebChatDriver` path.

The chain exposed two confirmed defects. First, a provider with valid cookies but zero discovered real models was exposed in the global provider selector and could be selected even though there was no valid model to send. Second, a stale persisted `selectedModel` survived live discovery and was returned by `MyCoderApp.effectiveSelectedModel`, allowing the composer/driver to propagate a removed model identifier. Round 68 fixes both with red-first regression tests.

## Button, action, and function checklist

| # | UI control/action | Chain traced | Expected behavior | Result |
|---:|---|---|---|---|
| 1 | Provider selector open | `ModelSettingsView` → `appState.providerOptions` | Show only usable providers, including web providers with valid sessions and real models. | **Fixed:** connected web configs with no discovered models are excluded. |
| 2 | Web provider option | `WebProviderConnectivity.providerOptions` → `ProviderOption(id: web:...)` | Include only non-expired session-backed providers with at least one discovered/explicit model. | **Fixed and tested:** cookie-only zero-model providers no longer appear. |
| 3 | Provider selection click | option row → `appState.selectProvider` → selection reconciliation | Select the web route and keep provider/model state coherent. | **Pass by source; native SwiftUI interaction UNVERIFIED.** |
| 4 | Web model catalog display | `modelsForSelectedProvider` → `WebProviderConnectivity.models` → `config.allModels` | Show live discovered and explicitly configured model IDs, not guessed catalog entries. | **Pass by source/tests; live vendor menus UNVERIFIED.** |
| 5 | Model row click | `WebProvidersSection`/model settings → `WebProviderSelectionLogic.selectingModel` → persisted `config.selectedModel` | Accept only a non-empty model present in the available real-model list. | **Pass:** unknown selections are ignored and valid selections persist. |
| 6 | Stale selected model | live discovery replaces config model list → `effectiveSelectedModel` | Fall back to the first real discovered model when the persisted identifier disappeared. | **Fixed:** `WebProviderSelectionLogic.effectiveSelectedModel` is wired into `MyCoderApp`. |
| 7 | Valid selected model | effective selection → composer/status/driver | Preserve a valid persisted model rather than changing it unnecessarily. | **Pass:** dedicated regression covers this. |
| 8 | Effort selector | `availableEfforts(for:)` → selected model profile | Show effort only for the selected live model’s advertised capabilities; hide unsupported/custom effort controls. | **Pass by source/tests; live vendor capability discovery UNVERIFIED.** |
| 9 | Effort row click | `selectingEffort` → persisted web config | Persist only an effort supported by the selected model. | **Pass:** unsupported values are ignored. |
| 10 | Login/capture session | Web Providers settings → `WebLoginSheet`/`WebSessionManager.persist` | Capture non-empty cookies and make the provider eligible only after a valid unexpired session exists. | **Pass by prior tests; native WebKit/login runtime UNVERIFIED.** |
| 11 | Expired session | `WebSessionManager.isExpired` → `isConnected` | Remove expired sessions from provider options and show the provider as unavailable. | **Pass:** expiry test remains green. |
| 12 | Refresh models | settings action → hidden WKWebView discovery → config persistence | Refresh real model/effort metadata and make the new model list affect selection. | **Pass by source/contract; live DOM/browser runtime UNVERIFIED.** |
| 13 | Send action | selected web option/model → `SendRouteResolver.web` → `ChatPanelView.runWebChatTurn` | Send through browser only after readiness, with effective model and effort propagated. | **Pass by prior routing/driver contracts; macOS/WebKit/provider runtime UNVERIFIED.** |
| 14 | No-model provider send prevention | zero-model config → provider selector and readiness | Avoid allowing a route that cannot produce a valid model request. | **Fixed at selector boundary; direct programmatic route/runtime remains guarded separately.** |
| 15 | Provider status summary | `WebProviderConnectivity.connectionSummary` | Report actual browser transport, model count, and delay without implying unavailable external transports. | **Pass after Round 66; native display UNVERIFIED.** |
| 16 | Provider deletion/update controls | Settings provider row → store persistence | Keep web config/session state coherent when edited or removed. | **Partial:** settings actions exist; native SwiftUI interaction and session cleanup require macOS verification. |

## Confirmed defects and TDD evidence

### 1. Cookie-only web providers were selectable

`WebProviderConnectivity.providerOptions` filtered only by session validity. A provider with non-expired cookies and an empty `allModels` list was therefore exposed in `MyCoderApp.providerOptions`, despite having no real model to display or send. `WebProviderAvailabilityLogicTests` was written first; the red run failed with a selectable zero-model provider. The green implementation adds `!models(for: $0).isEmpty` to the eligibility chain. Existing connectivity fixtures were updated to represent a connected provider with one real discovered model.

### 2. Stale persisted models propagated into send routing

`MyCoderApp.effectiveSelectedModel` returned any non-empty `cfg.selectedModel`, bypassing the already-correct `WebProviderSelectionLogic.selectedModel` fallback. After discovery removed a model, the composer and browser route could still carry that stale ID, causing model injection failure or misleading selection state. `WebProviderEffectiveModelLogicTests` was written first; the red run failed because no effective-model contract existed. The green helper preserves valid models and falls back to the first discovered real model, and `MyCoderApp` now uses it for web routes.

## Remaining limitations

WEB-06 remains **PARTIAL**. The Linux harness verifies session/model selection contracts, but cannot execute SwiftUI/AppKit controls, WebKit cookie restoration, vendor dropdown discovery, live ChatGPT/Kimi/Qwen pages, or provider-specific model availability. Providers with no live models are intentionally hidden rather than shown with a broken send path. The direct programmatic route can still be constructed outside the selector; runtime readiness and driver model injection remain the final safety boundary.

## Evidence and scores

| Check | Result | Boundary |
|---|---:|---|
| Red zero-model availability regression | **failed as expected** | Cookie-only provider was selectable |
| Green availability regressions | **2/2 passed** | Zero-model exclusion and real-model inclusion |
| Red stale-model regression | **failed as expected** | Effective-model helper absent |
| Green effective-model regressions | **2/2 passed** | Stale fallback and valid preservation |
| Full Foundation harness | **229/229 passed** | Existing contracts plus WEB-06 regressions |
| Swift parser validation | **passed** | Connectivity, selection logic, MyCoderApp wiring |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| Native SwiftUI/AppKit interaction | **UNVERIFIED** | Requires macOS runtime |
| Live WebKit/vendor model discovery | **UNVERIFIED** | Requires authenticated vendor pages |

The **implementation quality score is 94/100**. Provider eligibility now requires both a usable session and real models, while stale model propagation uses one tested source of truth. Native/live selection, store cleanup, and direct programmatic route boundaries remain.

The **task-following score is 100/100**. Every WEB-06 control and chain was traced, both confirmed defects received red tests before fixes, and runtime-dependent behavior remains explicitly UNVERIFIED.

> A provider is not ready merely because its cookies are valid; it is ready for the chat selector only when the app has at least one real model it can send to.
