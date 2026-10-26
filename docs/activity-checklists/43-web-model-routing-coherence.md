# Activity 43 — Web Model Discovery, Capability, and Routing Coherence

## Audit objective

This combined round audits **WEB-22 through WEB-27** from live DOM model discovery through strict candidate validation, nested “Expand more models” traversal, per-model effort/profile capability probing, selectable-versus-review-only state, persisted provider selection, local project/chat/session to remote chat UUID mapping, verified browser navigation, one-shot catalog refresh retry, duplicate-send prevention, and AI-assisted detection isolation.

The six stories remain PARTIAL because live vendor DOM/WebKit behavior cannot be executed in the Linux Foundation harness. The source audit nevertheless found three logical defects that were independently confirmed with red tests before fixes.

## Full chain checklist

| Story | Chain audited | Expected behavior | Result |
|---|---|---|---|
| WEB-22 | DOM candidates → visibility/selectability/leaf/disabled gates → parser normalize/validator → live model list | Headings, actions, effort labels, containers, disabled items, and invalid IDs never enter sendable `allModels`; rejected noise is explainable in source/tests. | **Pass by source/tests; live vendor DOM UNVERIFIED.** |
| WEB-23 | Dropdown open → candidate snapshots → exact expansion controls → fingerprint/count progression → deduplication → bounded depth | Every nested model branch behind supported expansion labels is traversed until no state progress remains, with bounded loops and no duplicate/noise entries. | **Pass by source/tests; live nested DOM UNVERIFIED.** |
| WEB-24 | Live model list → per-model selection → effort probe → parameter profile → `WebProviderModel` status → config refresh → composer/driver gates | A model owns its own efforts/profile/status; unsupported or undetected models hide effort and cannot be sent. | **Fixed Round 89; source/tests green; live capability probe UNVERIFIED.** |
| WEB-25 | Local provider/session/project/chat key → UserDefaults mapping → verified remote URL/UUID → browser navigation → journal metadata | Each local conversation maps to one verified remote chat; host/UUID mismatch fails closed; mappings cannot collide. | **Fixed Round 89 key collision; source/tests green; live provider routing UNVERIFIED.** |
| WEB-26 | Injection event → retry signal → same page/remote mapping → live model/effort refresh → one retry → completion/journal | Injection failure occurs before typing; one same-chat refresh/retry occurs without duplicate prompt or second remote chat; failure remains visible if retry cannot verify. | **Pass by source/tests; live WebKit failure injection UNVERIFIED.** |
| WEB-27 | AI page text → myCoder Auto Free extraction → strict normalization → review-only candidate → built-in DOM activation | AI may suggest review candidates but cannot invent or activate sendable models; only built-in DOM discovery persists selectable live models. | **Pass by source/tests; live AI/browser comparison UNVERIFIED.** |

## Detailed action and function trace

| # | Action/function | Chain and expected invariant | Result |
|---:|---|---|---|
| 1 | `WebModelDiscovery.discover` | Opens only catalog/custom selector, waits for control, uses structured visible leaf candidates, then strict text fallback. | **Pass by source/tests.** |
| 2 | `validatedNames` | Requires visible, selectable, non-disabled, leaf candidate and parser-valid normalized label; deduplicates case-insensitively. | **Pass by source/tests.** |
| 3 | `WebModelListParser.normalize` | Removes selection markers and rejects headings/actions/effort labels/vendor-invalid names. | **Pass by source/tests.** |
| 4 | `discoverAllModels` | Uses exact expansion labels, fingerprint-based state keys, bounded depth, and only appends newly validated names. | **Pass by source/tests.** |
| 5 | `discoverModelCapabilities` | Selects each model separately, marks failed selection inactive/unselectable, probes effort and parameters per model. | **Pass by source.** |
| 6 | `WebModelRefreshLogic.replacing` | Replaces stale live snapshot, deduplicates, preserves capability-probe status/selectability, and chooses only `allModels` entries. | **Fixed Round 89.** |
| 7 | `WebProviderConfig.allModels` | Includes selectable discovered models plus manual names; keeps review-only AI candidates visible but not sendable. | **Pass by source/tests.** |
| 8 | `availableEfforts` | Uses selected model’s profile; an undetected/manual/stale concrete model receives no aggregate effort leak. | **Fixed Round 89.** |
| 9 | `WebChatDriver.injectModelAndEffort` | Uses exact model option confirmation; after live profiles exist, skips effort injection for an undetected model. | **Fixed Round 89.** |
| 10 | `WebRemoteChatKey.storageKey` | Encodes the four identity components without delimiter ambiguity. | **Fixed Round 89.** |
| 11 | `WebRemoteChatStore.loadAll` | Reindexes legacy composite keys from mapping payloads into collision-safe keys. | **Pass by source.** |
| 12 | `bindWebRemoteChat` existing mapping | Verifies provider host, navigates to stored URL when needed, confirms exact remote UUID, updates last-used state. | **Pass by source; live WebKit UNVERIFIED.** |
| 13 | `bindWebRemoteChat` new mapping | Creates New Chat, verifies non-empty remote UUID and provider host, persists mapping before send. | **Pass by source; live vendor URL/UUID UNVERIFIED.** |
| 14 | `webCatalogRefreshReason` | Treats typed model/effort injection errors as retryable and generic errors only on conservative keywords. | **Pass by source.** |
| 15 | `retrySignal` path | Refreshes live models/effort, reloads config, retries once against the same bridge and mapping, and never creates a second assistant bubble. | **Pass by source; live failure injection UNVERIFIED.** |
| 16 | `completionSignal` gate | Only verified nonblank final events can mark the send complete after the retry path. | **Pass by source/tests.** |
| 17 | AI detection | Uses separate “Ask myCoder Auto Free” action; result normalization requires parser-valid labels and sets `isSelectable=false`. | **Pass by source.** |
| 18 | Built-in detection | Uses DOM discovery and `WebModelRefreshLogic.replacing`; no AI result is used as live activation input. | **Pass by source.** |
| 19 | AI save | AI candidates remain in `discoveredModels` for review and do not appear in `allModels`; no model is selected from AI output. | **Pass by source/tests.** |
| 20 | Native runtime | Actual menus, selectors, nested vendor DOM, UUID navigation, WebKit retry, and AI/browser comparison run on macOS. | **UNVERIFIED.** |

## Confirmed defects and TDD evidence

### WEB-24: effort capabilities leaked across models

`WebProviderSelectionLogic.availableEfforts` fell back to aggregate `discoveredEffortLevels` whenever the requested concrete model was not found in `discoveredModels`. A manually added, stale, or not-yet-detected model could therefore display an effort menu discovered for another model. `WebChatDriver.injectModelAndEffort` had the corresponding runtime leak: when profiles existed but the selected model was absent, it returned the persisted effort and clicked the page effort control anyway.

The red tests were added first. They required a manually added model to return no effort capabilities when another live model had `.high`, and required the driver not to click the effort option for an undetected model after a live profile snapshot existed. The fix now returns no effort for a concrete model without a verified profile; the driver preserves the old pre-discovery compatibility path only while no live profiles exist.

### WEB-24: refresh re-enabled unselectable capability results

`discoverModelCapabilities` correctly returned an inactive, unselectable model when the browser could not select it. `WebModelRefreshLogic.replacing` then overwrote that evidence by forcing every refreshed model to `.active`, `isLiveDiscovered=true`, and `isSelectable=true`, selecting the previously unverified entry as the active model.

The red refresh test passed an inactive/unselectable capability result and required the replacement snapshot to preserve its status, exclude it from `allModels`, and leave selection empty. The fix preserves the probe’s status and `isSelectable` flag, only promoting an unspecified `.notDetected` record to `.active` for ordinary successful discovery.

### WEB-25: remote-chat key delimiter collision

`WebRemoteChatKey.storageKey` joined provider, session, project, and local chat IDs with `::`. Distinct identities such as `activeSessionID=work::project, projectID=chat` and `activeSessionID=work, projectID=project::chat` produced the same key and could overwrite each other’s verified remote chat UUID.

The red test constructed exactly that collision. The fix encodes the four-component array as Base64 JSON, and `WebRemoteChatStore.loadAll` reindexes decoded legacy mapping payloads into the new key format. Host and exact remote UUID verification remain fail-closed in `bindWebRemoteChat`.

## Evidence

| Check | Result | Boundary |
|---|---:|---|
| Red WEB-24 effort fallback regression | **failed as expected** | Aggregate effort leaked to manual/undetected model |
| Green WEB-24 selection/driver tests | **15 tests passed across focused suites** | Model-aware composer/driver coherence |
| Red WEB-24 refresh selectability regression | **failed as expected** | Replacement forcibly re-enabled unselectable model |
| Green refresh suite | **3/3 passed** | Status/selectability/selection preserved |
| Red WEB-25 delimiter-collision regression | **failed as expected** | Composite key produced identical identities |
| Green WEB-25 runtime suite | **11/11 passed** | Collision-safe mapping and existing isolation |
| Full Foundation harness | **296/296 passed** | All previous rounds plus four WEB-22–WEB-27 regressions |
| Swift parser validation | **passed** | Discovery, parser, config, selection, driver, store, ChatPanel, views, and tests |
| Adversarial source checks | **12/12 passed** | Strict validation, exact injection, remote mapping, retry, AI isolation |
| `git diff --check` | **passed** | No trailing whitespace |
| Live vendor DOM and WebKit routing | **UNVERIFIED** | Requires macOS, authenticated sessions, and real vendor pages |

## Status and scores

`WEB-22` through `WEB-27` remain **PARTIAL** because the source-level contracts and Foundation tests cannot prove behavior against live vendor DOMs, WebKit navigation, authenticated sessions, real remote UUID changes, or the actual AI/browser comparison. The three confirmed logical defects in capability propagation and identity persistence are fixed and covered by red/green tests.

| Story | Code quality | Task adherence | Target-runtime confidence |
|---|---:|---:|---:|
| WEB-22 | 96/100 | 100/100 | 0/100 |
| WEB-23 | 96/100 | 100/100 | 0/100 |
| WEB-24 | 97/100 | 100/100 | 0/100 |
| WEB-25 | 97/100 | 100/100 | 0/100 |
| WEB-26 | 96/100 | 100/100 | 0/100 |
| WEB-27 | 96/100 | 100/100 | 0/100 |

> A model that is visible in a browser menu is not automatically safe to send: its
> selectability and effort capabilities must survive persistence and be confirmed again
> at injection time. Likewise, a local chat is not isolated until its remote UUID mapping
> is collision-safe and verified against the provider host and current URL.
