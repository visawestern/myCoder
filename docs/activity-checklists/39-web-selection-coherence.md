# Activity 39 — Web Selection Coherence

## Audit objective

This round audits **WEB-09 Web Selection Coherence** from the chat composer’s provider/model/effort controls through persisted `WebProviderConfig`, AppState reconciliation, effective-model presentation, send readiness, WebKit turn construction, `WebChatDriver` model/effort injection, exact browser confirmation, retry behavior, and completion journaling.

The canonical user story is: “As a user, I want the model and effort I select in the composer to be the exact values used by the embedded browser.” The prior rounds fixed the main provider-switch path and exact model injection. The fresh adversarial pass found three remaining coherence edges: global preferred-model restoration could override a valid destination-provider selection; effort capabilities were looked up against a stale persisted model instead of the effective model; and an explicitly empty live model list could echo a stale persisted model.

## Full chain checklist

| # | UI/control/action/function | Chain traced | Expected behavior | Result |
|---:|---|---|---|---|
| 1 | Provider selector | `ProviderSelectorMenu` → `AppState.selectProvider` | Selected provider ID is persisted and route identity remains provider-specific. | **Pass by source; native menu UNVERIFIED.** |
| 2 | Web model selector | `ModelSelectorMenu` → `modelsForSelectedProvider` → `selectModel` | Only the selected web provider’s current models are offered. | **Pass by source and tests.** |
| 3 | Web model persistence | `selectModel` → `updateWebProvider` → `WebProviderStore.save` | Composer selection is stored in `WebProviderConfig.selectedModel`. | **Pass by source and tests.** |
| 4 | Provider-local switch selection | provider switch → `WebSelectionReconciliationLogic.modelForRestore` | A valid destination model beats a shared global legacy model. | **Fixed Round 85; tested.** |
| 5 | Preferred-model restoration | `validateAndReconcileSelections` → `restorePreferredModelIfAvailable` | Global preference is used only when destination selection is stale. | **Fixed Round 85; tested.** |
| 6 | Empty live model snapshot | `selectedModel(... availableModels: [])` | No stale model ID is returned when live discovery has no models. | **Fixed Round 85; tested.** |
| 7 | Effective model display | `effectiveSelectedModel` → `ModelSelectionPresentationLogic.displayModel` | Composer label and checkmark use the same resolved model key. | **Pass by existing tests/source.** |
| 8 | Parameters identity | effective model → `parameterModelID` → model parameter store | Parameter popover edits the model actually selected for the route. | **Pass by existing tests/source.** |
| 9 | Web effort availability | `availableWebEffortsForSelectedProvider` | Effort options belong to the effective selected live model. | **Fixed Round 85; tested.** |
| 10 | Unsupported effort | persisted effort → `effortForModel` | Unsupported effort falls back to a confirmed model effort; no-effort model yields nil. | **Fixed Round 85; tested.** |
| 11 | Web effort menu | `WebEffortMenu` → `selectWebEffort` → config persistence | User-selected effort updates only the web provider config. | **Pass by existing tests/source.** |
| 12 | Agent variants separation | web effort vs server `VariantMenu` | Web effort is not mixed with server reasoning variants. | **Pass by source.** |
| 13 | Send validation | `SendReadinessLogic.sendValidationError` | Empty effective model blocks send with an actionable message. | **Pass by existing tests/source.** |
| 14 | Web route resolution | `SendRouteResolver` → `.web(configID)` | Selected web provider reaches the browser branch, not Serve fallback. | **Pass by existing tests/source.** |
| 15 | Config snapshot before browser | `runWebChatTurn` → `effectiveConfig` | Browser snapshot uses the composer’s effective model and reconciled effort. | **Fixed Round 85 by source; native runtime UNVERIFIED.** |
| 16 | Empty-safe browser model fallback | `WebProviderSelectionLogic.effectiveSelectedModel(... availableModels:)` | Stale config cannot survive an explicitly empty live list. | **Fixed Round 85; tested.** |
| 17 | Session selection | `effectiveConfig.activeSessionID` → `WebSessionManager.restore` | Browser uses the selected named login session. | **Pass by source; native cookies UNVERIFIED.** |
| 18 | Project/chat isolation | `webView(for:projectID:chatID:)` | Each project/chat/provider receives isolated browser state. | **Pass by existing tests/source.** |
| 19 | Browser model control | `WebChatDriver.injectModelAndEffort` → catalog/custom selector | Driver clicks the configured model control, not an effort control. | **Pass by existing tests/source.** |
| 20 | Exact model confirmation | `clickVisibleTextExact` | Requested model must be confirmed before typing; failure blocks send. | **Pass by existing tests/source; live DOM UNVERIFIED.** |
| 21 | Effort confirmation | effort dropdown → exact effort option | Requested effort is confirmed when the model exposes the control; failure blocks before typing. | **Pass by existing tests/source; live DOM UNVERIFIED.** |
| 22 | Model without effort | selected model capability list empty | Driver skips effort injection rather than showing a synthetic control. | **Pass by source and tests.** |
| 23 | Parameter injection | model profile → `injectParameters` | Saved parameters are sent only when live controls were discovered. | **Pass by source; live vendor controls UNVERIFIED.** |
| 24 | First message send | browser injection → type → send | No text is typed or sent before model confirmation. | **Pass by existing tests/source.** |
| 25 | Injection failure retry | model/effort failure → catalog refresh → retry | Refresh uses the same browser/chat identity and never creates a duplicate user turn. | **Pass by source and existing tests; live runtime UNVERIFIED.** |
| 26 | Completion journal | final config → `recordWebBrowserAction` | Journal records the exact final model, effort, local chat, and remote chat. | **Pass by source and tests.** |
| 27 | Native visual state | SwiftUI controls and hidden WebKit page | The visible selection and browser-confirmed selection match in a real authenticated session. | **UNVERIFIED; requires macOS/WebKit.** |

## Confirmed defects and TDD evidence

### Destination reconciliation could override a valid provider-local model

`AppState.selectProvider` already preferred a destination config’s valid model, but the later `restorePreferredModelIfAvailable` path used the global `preferredModelID` whenever it appeared in the destination’s model list. If two web providers shared a model ID, a valid destination-local selection could be overwritten by the global preference. `WebSelectionReconciliationLogic.modelForRestore` now centralizes the intended order: destination-local valid selection, global valid fallback, first available model, then empty.

### Effort capabilities could follow stale config state

`WebProviderSelectionLogic.availableEfforts(for:)` originally searched only for `config.selectedModel`. When the persisted model was stale but `effectiveSelectedModel` had already resolved to a live replacement, the effort menu could hide the replacement model’s capabilities or expose a union-level fallback. The helper now accepts an explicit model ID, and AppState passes the effective model.

### Empty live model lists could echo stale selection

`selectedModel(for:availableModels:)` previously returned `config.selectedModel` when the explicitly supplied model list was empty. The browser snapshot could therefore carry a stale model despite an empty live discovery result. The function now returns an empty ID for an explicitly empty list, and `runWebChatTurn` uses that empty-safe fallback.

### TDD sequence

`WebSelectionReconciliationLogicTests.swift` was written first; the red run failed because the missing helper did not exist. `WebProviderSelectionLogicTests` then added red cases for model-aware effort capabilities and empty live snapshots. The green implementation introduced the reconciliation helper, the model-aware effort parameter, AppState wiring, and an empty-safe model fallback. The focused WEB-09 suites passed with 16 tests, and the complete Foundation harness remained green.

## Evidence

| Check | Result | Boundary |
|---|---:|---|
| Red reconciliation regression | **failed as expected** | Missing destination/global selection contract |
| Red effort-capability regression | **failed as expected** | Helper lacked model-aware argument |
| Red empty-live-model regression | **failed as expected** | Stale persisted ID was returned for empty list |
| Green WEB-09 focused suites | **16/16 passed** | Reconciliation, model, effort, and driver guards |
| Full Foundation harness | **287/287 passed** | All previous rounds plus WEB-09 regressions |
| Swift parser validation | **passed** | Reconciliation, selection, AppState, InputControls, ChatPanel, tests |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| `git diff --check` | **passed** | No trailing whitespace |
| Native SwiftUI composer | **UNVERIFIED** | Requires macOS runtime |
| Live WebKit model/effort injection | **UNVERIFIED** | Requires authenticated vendor pages |
| Vendor DOM parameter controls | **UNVERIFIED** | Third-party page structure can change |

## Status and scores

`WEB-09` remains **PARTIAL**. Composer persistence, provider-local reconciliation, empty-safe model resolution, effective-model capability gating, exact browser injection guards, retry identity, and completion journaling are source-verified and contract-tested. Native SwiftUI behavior, authenticated WebKit execution, and live vendor DOM compatibility remain unverified.

| Dimension | Score | Rationale |
|---|---:|---|
| Implementation quality | 96/100 | One tested reconciliation source of truth now feeds provider restore, model fallback, effort capability, and browser snapshot construction; native/live behavior remains. |
| Task adherence | 100/100 | Every control, state mutation, persistence path, readiness gate, route, browser injection, retry, journal, and failure path was traced; red tests preceded the confirmed fixes; runtime boundaries remain explicit. |
| Target-runtime confidence | 0/100 | Linux cannot execute SwiftUI/AppKit/WebKit or authenticated vendor pages. |

> The composer must not merely display a selection; it must pass the same effective
> model and supported effort to the browser, or fail closed before typing.
