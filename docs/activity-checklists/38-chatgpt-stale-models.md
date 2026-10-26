# Activity 38 — ChatGPT Stale Models

## Audit objective

This round audits **BUG-03 ChatGPT Stale Models** from the web-provider configuration and bundled catalog through authenticated browser discovery, structured DOM candidates, text fallback, ChatGPT feature filtering, persisted model sanitization, refresh replacement, provider-option availability, selected-model fallback, browser model injection, and the visible Settings refresh/detection actions.

The canonical story is: “As a ChatGPT user, I want only live models and no stale feature entries.” The prior source review had already removed ChatGPT static catalog guesses and filtered feature actions such as Deep Research, Image, and Canvas. The fresh adversarial pass found a remaining lifecycle defect: an empty live discovery result did not replace the previous stored snapshot. `WebModelListParser.updated` preserved stale entries, and `AppState.refreshWebModels` returned before persisting an authoritative empty result.

## Full chain checklist

| # | UI/control/action/function | Chain traced | Expected behavior | Result |
|---:|---|---|---|---|
| 1 | Web provider configuration | `WebChatVendor.chatgpt` → `WebProviderConfig` | ChatGPT starts with no guessed static model list. | **Pass by source and existing test.** |
| 2 | Bundled ChatGPT catalog | `web_providers_catalog.json` → selectors/URL | Catalog supplies navigation and selectors, not model guesses. | **Pass by source; live page compatibility UNVERIFIED.** |
| 3 | Persisted config load | `WebProviderStore.load` → `sanitize` | Older stored labels are normalized and invalid UI labels removed. | **Pass by source and existing tests.** |
| 4 | ChatGPT feature filtering | `WebModelListParser.isChatGPTModelLabel` | Deep Research, Image, Canvas, Search, Study, Shopping, Tasks, Projects, and Voice do not enter the model list. | **Pass by source and existing tests.** |
| 5 | Generic UI-noise filtering | `isValidModelLabel` | “Model”, “Model Comparison”, “Expand more models”, settings, upgrade, and effort labels are rejected. | **Pass by source and existing tests.** |
| 6 | ChatGPT model-family validation | `isChatGPTModelLabel` | Only GPT/o1/o3/o4-style labels survive ChatGPT validation. | **Pass by source; current vendor labels UNVERIFIED.** |
| 7 | Structured DOM discovery | `WebModelDiscovery.discover` → visible/selectable/leaf candidates | Only visible selectable leaf options are normalized and persisted. | **Pass by source; live DOM UNVERIFIED.** |
| 8 | Text fallback | dropdown text → `WebModelListParser.parse` | Fallback remains strict and cannot bypass vendor validation. | **Pass by source and tests.** |
| 9 | Expand more models | `discoverAllModels` → bounded expansion loop | Nested/secondary model menus are expanded with deduplication and bounded depth. | **Pass by source; live DOM UNVERIFIED.** |
| 10 | Empty dropdown result | discovery returns `[]` | Completed empty live snapshot must clear stale auto-discovered models. | **Fixed Round 84.** |
| 11 | Browser/discovery failure | discovery returns `nil` or throws | Transport/page failure returns an actionable error and may preserve the last known snapshot. | **Pass by source; native WebKit failure UX UNVERIFIED.** |
| 12 | Parser refresh helper | `WebModelListParser.updated` | Empty parsed result replaces, rather than preserves, old discovered models. | **Fixed Round 84; tested.** |
| 13 | Atomic refresh contract | `WebModelRefreshLogic.replacing` | Fresh models are deduplicated, normalized, marked live/selectable, and stale entries are dropped. | **Fixed Round 84; tested.** |
| 14 | Selected model after empty refresh | replacement → `selectedModel` | Selection becomes empty unless an explicit manual model remains. | **Fixed Round 84; tested.** |
| 15 | Selected model after changed refresh | replacement → `allModels.first` | A removed selected model falls back to the first fresh model. | **Fixed Round 84; tested.** |
| 16 | Valid selection after refresh | changed snapshot containing selected model | The replacement remains deterministic; no stale entry survives. | **Pass by replacement contract.** |
| 17 | Per-model effort recomputation | fresh model capabilities → `discoveredEffortLevels` | Effort levels reflect only the fresh snapshot, not stale models. | **Pass by source; live capability probing UNVERIFIED.** |
| 18 | Chat input provider options | `WebProviderConnectivity.providerOptions` | Connected ChatGPT appears only when its model list is non-empty. | **Pass by source and existing tests.** |
| 19 | Chat input model list | `models(for:)` → `config.allModels` | Bundled catalog guesses are not exposed as sendable models. | **Pass by source.** |
| 20 | Provider switch | `AppState.selectProvider` → `modelForProviderSwitch` | Provider-local live model wins over the global legacy model. | **Pass by existing tests/source.** |
| 21 | Effective model | `AppState.effectiveSelectedModel` | Composer and browser driver use the same selected live model. | **Pass by existing tests/source.** |
| 22 | Invalid model selection | `selectingModel` | A model absent from the current list cannot silently replace selection. | **Pass by existing tests/source.** |
| 23 | Browser model injection | `WebChatDriver.runTurn` → model selector click | Send is blocked when model confirmation fails; no duplicate send occurs. | **Pass by existing tests; live browser UNVERIFIED.** |
| 24 | Refresh button | `WebProvidersSection.refreshModels` → `AppState.refreshWebModels` | User sees a success/failure message and stored catalog updates atomically. | **Pass by source; native UI interaction UNVERIFIED.** |
| 25 | Built-in DOM detection | `findModelsBuiltIn` | Empty completed discovery clears stale state and shows “No models found”. | **Fixed Round 84.** |
| 26 | AI-assisted detection | `findModelsWithAI` → `saveDetectedModels` | AI candidates are filtered and remain unselectable until DOM verification. | **Pass by source and adversarial check.** |
| 27 | AI candidate merge | `saveDetectedModels` | Candidate labels do not become sendable models without live verification. | **Pass by source; AI runtime UNVERIFIED.** |
| 28 | Login/session boundary | `WebSessionManager.restore` → cookies/localStorage → web view | Refresh uses the selected named session, not an unrelated login. | **Pass by source; native cookies UNVERIFIED.** |
| 29 | Repeated refresh | store upsert by provider ID | Refresh replaces the provider snapshot rather than appending duplicate stale records. | **Pass by source and replacement tests.** |
| 30 | Native rendering and live account | SwiftUI/WebKit/vendor page | Actual ChatGPT model names and feature controls are verified in the authenticated browser. | **UNVERIFIED; requires macOS and live account.** |

## Confirmed defect and TDD evidence

### Empty live refresh preserved stale ChatGPT models

The old parser helper only assigned `discoveredModels` when parsing returned a non-empty list. Therefore, a dropdown containing only feature/UI entries left the previous stale model snapshot untouched. The AppState refresh path had a second guard, `guard let found = models, !found.isEmpty`, which returned before persistence when discovery completed with an empty array.

The combined effect violated the user story: after a refresh that found no real ChatGPT models, the UI could continue to expose the old model snapshot and selected model. A failed browser operation (`nil`/throw) remains distinct from an authoritative empty live menu; the former reports failure without pretending a new snapshot was obtained, while the latter clears stale auto-discovered state.

### TDD sequence

`WebModelRefreshLogicTests.swift` was written before the production helper and initially failed to compile because `WebModelRefreshLogic` did not exist. After the helper was implemented, the focused suite passed its empty and changed-snapshot cases. A caller-level red regression was then added to `WebModelListParserTests`: an empty ChatGPT parse containing only “ChatGPT”, “Deep Research”, and “Canvas” initially left `gpt-stale` selected. Wiring `updated` to the helper made the test pass.

The Settings built-in detector and AppState refresh now use the same replacement contract. A stale parser fixture for custom providers was also corrected: the existing strict validator intentionally rejects unidentifiable labels such as `a`, `b`, and `c`, so its separator test now uses valid versioned model IDs.

## Evidence

| Check | Result | Boundary |
|---|---:|---|
| Red `WebModelRefreshLogicTests` | **failed as expected** | Replacement contract absent before implementation |
| Red caller-level empty ChatGPT refresh | **failed as expected** | Parser preserved stale model and selection |
| Green refresh/parser suites | **11/11 passed** | Empty, changed, feature-filtered, deduplicated, and parser cases |
| Full Foundation harness | **281/281 passed** | All prior contracts plus BUG-03 regressions |
| Swift parser validation | **passed** | New helper, parser, AppState, Settings detector, and tests |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| `git diff --check` | **passed** | No trailing whitespace |
| Live ChatGPT model discovery | **UNVERIFIED** | Requires authenticated macOS WebKit session |
| Native Settings refresh interaction | **UNVERIFIED** | Requires macOS SwiftUI runtime |
| Third-party selector compatibility | **UNVERIFIED** | Vendor DOM can change independently of source contracts |

## Status and scores

`BUG-03` remains **PARTIAL**. Static catalog guesses, feature-entry filtering, provider availability gating, atomic replacement, and stale-selection fallback are now source-verified and contract-tested. Live ChatGPT discovery did not execute in this Linux environment, so the actual account-specific model list and WebKit selector compatibility remain unverified.

| Dimension | Score | Rationale |
|---|---:|---|
| Implementation quality | 96/100 | One atomic replacement contract is reused by parser, AppState refresh, and Settings detector; empty and changed snapshots are safe; live DOM and native UI remain unverified. |
| Task adherence | 100/100 | Every discovery, filter, refresh, persistence, selection, send, AI-candidate, and failure chain was traced; red tests preceded both confirmed fixes; documentation and registry are updated. |
| Target-runtime confidence | 0/100 | Linux cannot execute authenticated macOS WebKit/SwiftUI or the real ChatGPT page. |

> A failed discovery must not masquerade as success, but a completed empty live snapshot
> must not leave yesterday’s model list presented as current.
