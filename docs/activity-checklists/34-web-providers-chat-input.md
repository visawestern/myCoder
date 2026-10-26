# Activity 34 — Web Providers in Chat Input

## Audit objective

This round audits **WEB-06 Web Providers in Chat Input** from web-provider persistence and captured-session eligibility through live model discovery, zero-model filtering, provider-option construction, provider switching, selected-model fallback, effort capability display, model menu state, connection readiness, send validation, WebChatDriver injection, and native composer presentation.

Round 68 already fixed two important defects: cookie-only providers with zero real models were shown as selectable, and stale persisted web model IDs were propagated instead of falling back to a discovered model. The fresh audit found one remaining provider-switch defect: selecting a web provider could reuse the global model ID from the previously selected provider whenever that ID happened to exist in the new provider’s model list, overriding the new provider’s own persisted selection.

## Full chain checklist

| # | UI/control/action/function | Chain traced | Expected behavior | Result |
|---:|---|---|---|---|
| 1 | Provider storage | `WebProviderStore.load/save/sanitize` | Restore provider config, normalize discovered models, and clear stale selected model IDs. | **Pass by source/tests.** |
| 2 | Session capture | `WebSessionManager.persist` → provider-specific session | A provider is not considered connected merely because it was configured. | **Pass by source/tests; native browser capture UNVERIFIED.** |
| 3 | Cookie expiry | `WebProviderConnectivity.isConnected` → `WebSessionManager.isExpired` | Expired/empty cookie sessions are excluded from chat input. | **Pass by source/tests.** |
| 4 | Real-model eligibility | `models(for:)` → `providerOptions` | Connected providers with no live/manual model are excluded from the selector. | **Pass by existing Round 68 tests/source.** |
| 5 | Provider option identity | config ID → `web:<id>` | Preserve a stable namespace so web selection cannot collide with local/server IDs. | **Pass by source/tests.** |
| 6 | Provider selector | `AppState.providerOptions` → `ProviderSelectorMenu` | Show only eligible web providers with a visible web label and connected state. | **Pass by source; native SwiftUI UNVERIFIED.** |
| 7 | Provider switch | `selectProvider` → config lookup → selected model persistence | On switching providers, use the destination provider’s valid persisted model before considering any global legacy value. | **Fixed Round 80:** provider-specific persisted selection now wins. |
| 8 | Stale destination model | provider config → `modelForProviderSwitch` | If persisted model is stale, fall back to a valid global model only when it exists in the destination list, otherwise first real model. | **Pass by new contract and existing fallback tests.** |
| 9 | Model selector | `modelsForSelectedProvider` → `ModelSelectorMenu` | Show only the selected web provider’s real discovered/manual models. | **Pass by source/tests; native menu UNVERIFIED.** |
| 10 | Selected model marker | `effectiveSelectedModel` → `ModelSelectionPresentationLogic` | Mark the effective destination model, not a stale global ID. | **Pass by existing tests/source.** |
| 11 | Effort selector | selected config → `availableEfforts` | Hide custom effort when the selected model exposes no capability; never invent a global effort list before discovery. | **Pass by existing tests/source.** |
| 12 | Web connection readiness | web session + model + selected provider | A connected provider still fails closed if no effective model exists. | **Pass by source/tests; native message UNVERIFIED.** |
| 13 | Send readiness | `SendReadinessLogic` → `SendProviderReadinessLogic` | Model/provider/session errors must block both button and keyboard send. | **Pass by existing tests/source.** |
| 14 | Browser injection | config selected model/effort → `WebChatDriver` | Confirm selected model and optional effort in the live page before typing/sending. | **Pass by source/tests; vendor DOM UNVERIFIED.** |
| 15 | Injection failure | model/effort click failure → `WebChatEvent` | Do not type or click Send after failed confirmation; surface a provider-specific status. | **Pass by source/tests.** |
| 16 | Web response path | browser bridge → completion journal → chat message | Preserve provider/model/session routing metadata and final answer. | **Pass by source/tests; live WebKit UNVERIFIED.** |
| 17 | Refresh/discovery | model discovery → provider config persistence | Successful discovery updates the provider’s real model list; failed empty discovery must not wipe a known-good list. | **Pass by source; live vendor DOM UNVERIFIED.** |
| 18 | Offline/zero-model selection | hidden provider option → current selection reconciliation | The selector must not offer a provider that cannot send. Existing reconciliation falls back when options are available; live transition remains unverified. | **PARTIAL:** runtime discovery and native state refresh remain unverified. |

## Confirmed defect and TDD evidence

### Provider switching reused the global model over the destination provider’s persisted choice

`AppState.selectProvider` previously examined the global `selectedModel` first. If a model ID from provider A also appeared in provider B’s model list, switching to provider B selected the global ID even when provider B had a different valid persisted `selectedModel`. This made the composer and browser route appear to switch providers while silently changing the destination provider’s remembered model.

A red regression was added to `WebProviderSelectionLogicTests` before implementation. It failed because no provider-switch model contract existed. The green implementation adds `modelForProviderSwitch(config:globalSelectedModel:availableModels:)`, which prefers the destination config’s valid selection, then a valid global fallback, then the first available model. `AppState.selectProvider` now consumes that contract and persists the resulting model consistently.

## Evidence and scores

| Check | Result | Boundary |
|---|---:|---|
| Red provider-switch regression | **failed as expected** | Destination-specific selection contract absent before implementation |
| Green WEB-06 selection suite | **10/10 passed** | Provider switch, selection, effort, injection, and custom vendor coverage |
| Full Foundation harness | **261/261 passed** | Existing contracts plus WEB-06 regression |
| Swift parser validation | **passed** | Selection logic and AppState wiring |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| Native SwiftUI composer/menus | **UNVERIFIED** | Requires macOS runtime |
| Live WebKit model discovery and send | **UNVERIFIED** | Requires authenticated vendor pages |

`WEB-06` remains **PARTIAL**. Session/model eligibility, zero-model filtering, stale-model fallback, provider-specific switch selection, effort capability gating, and browser injection guards are contract-tested. Native menus, live vendor discovery, cookie restoration, and real ChatGPT/Kimi/Qwen send behavior remain unverified.

The **implementation quality score is 95/100**. Provider identity and model selection now have one tested source of truth; native/live runtime and dynamic zero-model transitions remain.

The **task-following score is 100/100**. Every WEB-06 selector, state transition, discovery action, send gate, browser injection, and persistence path was traced; the confirmed defect received a red test before the fix; documentation was updated; and runtime-only behavior remains explicitly UNVERIFIED.

> Switching providers must switch to the destination provider’s valid model context, not leak a same-named model from the previous provider through global state.
