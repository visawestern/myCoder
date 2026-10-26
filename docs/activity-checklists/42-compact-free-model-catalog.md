# Activity 42 — Compact Free Model Catalog

## Audit objective

This round audits **MODEL-19 Compact Free Model Catalog** from the anonymous OpenCode `/models` response through free-model trust filtering, ordering, metadata/profile construction, store refresh, selected-model persistence, lock/unlock behavior, failover, status messaging, the compact selected summary row, dense switch menu, refresh button, system-prompt controls, send-route selection, and visible availability state.

The canonical story is: “As a user, I want the free-model catalog to show the current model first and switch models from a compact list.” The expected behavior is one compact selected-model summary row, every available live model accessible from a dense switch list with status, and lock/unlock available only for the selected model. Round 48 implemented that UI structure. The adversarial pass found one trust-boundary defect in the catalog filter: `isEligibleFreeModel` accepted any arbitrary ID ending in `-free`, although the provider contract stated that only the official temporary free-model IDs may be selected automatically.

## Full chain checklist

| # | UI/control/action/function | Chain traced | Expected behavior | Result |
|---:|---|---|---|---|
| 1 | Provider section mount | `UnifiedProvidersView` → `MyCoderAutoFreeSection` | Built-in Auto Free provider appears as a dedicated settings section. | **Pass by source; native UI UNVERIFIED.** |
| 2 | Provider identity | `MyCoderAutoFreeProvider.builtInID` / display name | Provider is `mycoder-auto-free` and shown as myCoder Auto Free. | **Pass by source and existing tests.** |
| 3 | Live catalog fetch | `Refresh catalog` → `MyCoderAutoFreeStore.refreshModels` → `MyCoderAutoFreeClient.listModels` | Anonymous catalog is refreshed without API key and failure is visible. | **Pass by source; live endpoint UNVERIFIED.** |
| 4 | HTTP/status validation | `/models` response → `validate` | Non-2xx, invalid response, and timeout fail without synthetic catalog entries. | **Pass by source.** |
| 5 | JSON decode | `ModelListResponse.data` → DTO map | Model IDs, context length, and descriptions are preserved when reported. | **Pass by source.** |
| 6 | Trusted free filtering | DTO IDs → `isEligibleFreeModel` | Only official temporary free IDs enter the selectable catalog. | **Fixed Round 88; tested.** |
| 7 | Paid model rejection | catalog ID such as `gpt-5.5` or `claude-opus-5` | Paid/non-free IDs never enter the Auto Free selection list. | **Pass by source and existing tests.** |
| 8 | Arbitrary `-free` rejection | unknown `untrusted-random-free` | A suffix alone is not proof of temporary free eligibility. | **Fixed Round 88; tested.** |
| 9 | Official ordering | `freeModelIDs` + sorted live additions → `orderedIDs` | Big Pickle is first when live; official alternatives retain deterministic preference order. | **Pass by source and existing tests.** |
| 10 | Duplicate removal | `freeModelIDs + liveFreeIDs.filter` | Duplicate IDs occur once in the catalog. | **Pass by source.** |
| 11 | Empty catalog | no eligible models → `noFreeModels` | Provider becomes unavailable; no synthetic Big Pickle row is offered. | **Pass by source and existing tests.** |
| 12 | Store apply | `applyCatalog` → `provider.models` | Catalog replaces live model state and purges statuses for removed IDs. | **Pass by source.** |
| 13 | Selected-model reconciliation | selected ID absent → first live model or default only when empty | Stale selected model is replaced and lock is cleared. | **Pass by source.** |
| 14 | Lock persistence | `setModelLocked` → UserDefaults | Lock is persisted only when the selected model exists in the current catalog. | **Pass by source.** |
| 15 | Selected model persistence | `selectModel` → UserDefaults → `appState.selectModel` | Selected live model survives restart and reaches the composer when Auto Free is selected. | **Pass by source and existing tests.** |
| 16 | Compact selected row | `modelCatalog` → `Menu` label | Only current model name/ID/status is shown in the closed catalog row. | **Pass by source; visual density UNVERIFIED.** |
| 17 | Dense switch list | Menu `ForEach(store.provider.models)` | Every live selectable model is available from the compact switching list. | **Pass by source; native hit target UNVERIFIED.** |
| 18 | Current marker | selected model → checkmark/lock icon | Current model is visually distinguished in the switch list. | **Pass by source.** |
| 19 | Per-model status | `modelStatus(for:)` → menu text | Active, pinned, live, failed, rate-limited, and unavailable states are visible. | **Pass by source.** |
| 20 | Lock selected model | lock button/toggle → `setModelLocked` | Lock/unlock is available only for the selected model and changes failover policy. | **Pass by source.** |
| 21 | Automatic failover | stream error → failure count → `shouldSwitch` | Rate-limit/model-unavailable errors switch immediately; generic failures switch at five. | **Pass by source and existing tests.** |
| 22 | Pinned failure | locked model error → terminal failure | Pinned model does not silently switch; user sees unlock guidance. | **Pass by source.** |
| 23 | Failover notification | model switch → `NotificationCenter` + status line | User sees from/to model and reason. | **Pass by source and existing tests.** |
| 24 | Refresh failure | listModels error → last-known catalog/status | Transient refresh failure does not fabricate a new model; status explains failure. | **Pass by source.** |
| 25 | Provider readiness | `isCatalogReady && !models.isEmpty` | Offline state is shown when no trusted live catalog exists. | **Pass by source and existing tests.** |
| 26 | System prompt | TextEditor → `setSystemPrompt` → request insertion | Prompt is saved and sent before each Auto Free request. | **Pass by source and existing tests.** |
| 27 | Privacy/availability note | `privacyNote` | Temporary availability and data-use caveats remain visible. | **Pass by source; native UI UNVERIFIED.** |
| 28 | Send route | selected Auto Free provider → `SendRouteResolver.autoFree` | Chat send uses Auto Free direct route and does not fall through to Serve. | **Pass by source and existing tests.** |
| 29 | Current model request | provider selection → `streamChat(model:)` | Request uses the exact selected/failover model, never a paid fallback. | **Pass by source.** |
| 30 | Native visual result | SwiftUI Menu/Toggle/refresh in macOS | Compact row, dense menu, lock control, and status fit correctly and are usable. | **UNVERIFIED; requires macOS.** |

## Confirmed defect and TDD evidence

### Arbitrary `-free` IDs were trusted

The provider’s comments and tests stated that only official temporary free-model IDs are eligible. However, `isEligibleFreeModel` returned true for every ID ending in `-free`. Because `listModels` computed `liveFreeIDs` through that function, an arbitrary or later-paid catalog entry with a misleading suffix could enter `orderedIDs`, become selectable, be persisted, and reach `chatCompletion`.

`MyCoderAutoFreeEligibilityTests.swift` was written first. The red test required `untrusted-random-free` to be rejected while retaining `big-pickle` and `mimo-v2.5-free`; it failed because the suffix heuristic returned true. The implementation now uses `freeModelIDs.contains(modelID)`, making the trust boundary explicit and consistent with the provider’s documented temporary allow-list. The existing live catalog remains refreshable for metadata and availability; only trusted IDs become selectable.

### Compact UI chain review

The active `MyCoderAutoFreeSection.modelCatalog` uses one selected summary row and a `Menu` containing every current provider model, with status and a selected-model lock button. `AutoFreeCompactModelRow` and `AutoFreeModelCard` are currently unused declarations, so the audit does not claim that they are the visible UI. The active Menu path is the canonical implementation for MODEL-19. Native menu density, hit targets, and visual clipping remain unverified without macOS.

## Evidence

| Check | Result | Boundary |
|---|---:|---|
| Red untrusted `-free` regression | **failed as expected** | Suffix heuristic admitted arbitrary ID |
| Green MODEL-19 eligibility test | **1/1 passed** | Official IDs accepted; arbitrary suffix rejected |
| Full Foundation harness | **292/292 passed** | All previous rounds plus MODEL-19 regression |
| Swift parser validation | **passed** | Auto Free client/provider/UI and tests |
| Adversarial source checks | **12/12 passed** | Catalog/model/browser invariants remained green |
| `git diff --check` | **passed** | No trailing whitespace |
| Live OpenCode `/models` payload | **UNVERIFIED** | Endpoint returned HTTP 403 in sandbox; no live catalog claim made |
| Native compact Menu/Toggle layout | **UNVERIFIED** | Requires macOS SwiftUI runtime |
| Live anonymous Auto Free send/failover | **UNVERIFIED** | Requires live provider endpoint and SSE response |

## Status and scores

`MODEL-19` remains **PARTIAL**. Trusted free-ID filtering, live metadata refresh, deterministic ordering, compact selected summary, dense switch list, per-model status, selected-only lock, persistence, failover, send routing, and readiness are source-verified and contract-tested. Live catalog contents, real provider availability, native visual density, and macOS interaction remain unverified.

| Dimension | Score | Rationale |
|---|---:|---|
| Implementation quality | 96/100 | The trust boundary now matches the documented official allow-list and the compact active Menu path remains unchanged; live catalog/native UI remain. |
| Task adherence | 100/100 | Provider discovery, filtering, ordering, selection, lock, refresh, failover, status, prompt, route, and active UI were traced; red test preceded the fix; runtime limits are explicit. |
| Target-runtime confidence | 0/100 | Linux cannot execute SwiftUI or verify a live OpenCode anonymous catalog/send. |

> A model is not free merely because its identifier says “free.” The selectable catalog
> must be limited to IDs the provider contract explicitly trusts, then refreshed for
> current availability and metadata.
