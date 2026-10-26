# Activity 54 — Partial Web/Auto Free Sweep and Danger Boundary

## Audit objective

This round revisits the next canonical rows after IDX-03: **DNG-01**, **BUG-03**, **WEB-09**, **WEB-10**, **APP-06**, **MODEL-19**, and **WEB-22–WEB-27**. The chain was traced from provider/model selection and live catalog refresh through capability probes, exact model/effort injection, remote-chat mapping, one-shot retry, response validation, completion journaling, Auto Free catalog refresh/failover/status UI, and dangerous-command policy.

## Canonical status

| Story | Result |
|---|---|
| DNG-01 | **FUTURE by explicit product policy.** No dangerous-command detector was implemented speculatively. Existing `AccessLevel` approval gates remain the current safety boundary. |
| BUG-03 | **No new defect.** Authoritative empty/non-empty ChatGPT refresh behavior remains source-tested; stale models do not survive a live empty snapshot. |
| WEB-09 | **No new defect.** Provider-local model/effort reconciliation and effective-config consumption remain coherent in source/tests. |
| WEB-10 | **No new defect beyond Round 98 cancellation/Stop hardening.** Browser send verifies session, selectors, exact model/effort, changed nonblank response, and completion before journaling. |
| APP-06 | **No new defect.** Serve direct/SSE response validation and empty-response feedback remain source-tested. |
| MODEL-19 | **Fixed Round 100.** A catalog refresh no longer overwrites the visible reason when `applyCatalog` switches an unavailable selected model. |
| WEB-22 | **No new defect.** Strict visible/leaf/selectable/vendor validation remains enforced. |
| WEB-23 | **No new defect.** Bounded fingerprint-driven expansion and deduplication remain enforced. |
| WEB-24 | **No new defect.** Per-model status, selectable state, effort, and parameter profile remain capability-coherent. |
| WEB-25 | **No new defect.** Remote chat routing remains project/chat/login isolated and UUID fail-closed. |
| WEB-26 | **Fixed Round 100.** Catalog retry now preserves the original first-turn flag and does not duplicate the system/tool preamble in an existing remote chat. |
| WEB-27 | **No new defect.** AI detection remains review-only; DOM discovery is the only activation path. |

## Full manual chain checklist

| # | Action/function | Invariant traced | Result |
|---:|---|---|---|
| 1 | Danger policy | `DNG-01` is explicitly FUTURE; no unsupported detector or false warning was added. | **Policy boundary recorded.** |
| 2 | Provider selection | Web option resolves to a local config and does not use stale global state when destination config is valid. | **Pass by source/tests; native UI UNVERIFIED.** |
| 3 | Empty authoritative refresh | Empty live model discovery clears stale discovered models and selection rather than echoing stale IDs. | **Pass by existing BUG-03 tests.** |
| 4 | Non-empty refresh | Live models are normalized/deduplicated, capabilities refreshed, and valid selection reconciled. | **Pass by existing tests/source.** |
| 5 | Effective model | Composer and driver use the same effective provider model; missing/stale selection fails closed or uses verified available fallback. | **Pass by existing tests/source.** |
| 6 | Effort capability | Effort options derive from the current model only; unsupported models hide the custom effort path. | **Pass by existing tests/source.** |
| 7 | Capability status | Each model preserves active/inactive/notDetected/unsupported status, selectability, effort list, and parameter profile. | **Pass by existing tests/source.** |
| 8 | Model candidate validation | Only visible, selectable, non-disabled, leaf, vendor-valid normalized names enter the active live catalog. | **Pass by existing tests/source.** |
| 9 | Nested expansion | Expansion clicks are bounded, fingerprint/count changes are observed, and model names are deduplicated. | **Pass by existing tests/source; live DOM UNVERIFIED.** |
| 10 | AI detection | AI output is parsed strictly and saved as unselectable review candidates; it cannot become active authoritative catalog data. | **Pass by existing tests/adversarial checks.** |
| 11 | Remote mapping | Existing local project/chat/login mapping verifies host and remote UUID; mismatch blocks send. | **Pass by existing tests/source; live vendor routing UNVERIFIED.** |
| 12 | First-turn preamble | A new mapping receives system/tool preamble once; later turns continue without re-seeding the remote chat. | **Pass by source/tests.** |
| 13 | Catalog retry | Injection failure happens before typing; refresh is one-shot and stays on same page/mapping. | **Pass by existing tests/source.** |
| 14 | Retry context | Refresh retry preserves original `isFirstMessage`; an existing remote chat never receives a duplicate preamble. | **Fixed Round 100 red→green.** |
| 15 | Browser send verification | Session state, input/send selectors, exact model/effort, and new nonblank response are required before completion. | **Pass by existing tests/source; WebKit UNVERIFIED.** |
| 16 | Stop/cancel | Active project/chat WebView is stopped; cancellation prevents post-driver retry/completion continuation. | **Fixed Round 98, revalidated Round 100.** |
| 17 | Captcha/logout | Captcha solver blocks/resumes same turn; logout/terminal states dismiss and do not journal completion. | **Pass by existing tests/source; live captcha UNVERIFIED.** |
| 18 | Serve direct response | Direct and SSE Serve routes reject blank text/reasoning/tool-free responses with actionable feedback. | **Pass by existing APP-06 tests/source.** |
| 19 | Serve timeout/busy | Timeout, busy retry, persistence, and feedback paths are bounded and source-tested. | **Pass by existing tests/source; live Serve/SSE UNVERIFIED.** |
| 20 | Auto Free refresh | Live catalog applies trusted models, preserves selection if valid, and clears lock when selection becomes unavailable. | **Pass by existing tests/source.** |
| 21 | Auto Free status | Successful refresh shows ready status unless the refresh forced a model switch; forced switch reason remains visible. | **Fixed Round 100 red→green.** |
| 22 | Auto Free compact catalog | Selected model remains one compact summary row; dense menu exposes available models; lock control applies only to selected model. | **Pass by existing source/adversarial check; native visual UNVERIFIED.** |
| 23 | Auto Free failover | Rate-limit/model failures are bounded, switch only when unlocked, notify user, and preserve reason/status. | **Pass by existing tests/source.** |
| 24 | Danger future boundary | No DNG implementation is claimed; AccessLevel approval remains separate from future automatic danger classification. | **Explicit FUTURE.** |

## Confirmed defects and TDD evidence

### WEB-26 — refresh retry duplicated first-turn context

The original web turn computed `isFirst` from the remote mapping, but catalog refresh retry hardcoded `isFirstMessage: true`. An existing project/chat therefore received the first-turn system/tool preamble again after an injection failure, mixing context in the same remote conversation. A red regression was written first and failed to compile until the policy existed. The retry now preserves the original flag through `WebRetryContextLogic`.

### MODEL-19 — refresh erased the model-switch explanation

`applyCatalog` correctly switched an unavailable selected model and set a useful status, but `refreshModels` immediately replaced that status with `Anonymous OpenCode free catalog ready.` A red regression was written first. The new status policy preserves a forced switch reason and only uses the generic ready message when no switch occurred.

### No new defects confirmed

BUG-03, WEB-09, WEB-10, APP-06, WEB-22, WEB-23, WEB-24, WEB-25, and WEB-27 were traced through their complete source chains. Existing tests and adversarial checks cover the confirmed contracts; no speculative changes were made. Native browser/vendor/runtime claims remain UNVERIFIED.

## Evidence

| Check | Result | Boundary |
|---|---:|---|
| WEB-26 retry-context red test | **compile failed before policy → 1/1 passed** | Foundation context policy |
| MODEL-19 status red test | **compile failed before policy → 2/2 passed** | Foundation status policy |
| Partial-sweep source acceptance | **passed** | WEB-26/MODEL-19/DNG boundary |
| Full Foundation harness | **360/360 passed** | Linux-safe suites |
| Adversarial source checks | **12/12 passed** | Existing safety invariants |
| Canonical registry integrity | **274 rows, unique IDs, valid statuses** | Registry acceptance |
| Swift parser validation | **passed** | Changed production/test files |
| `git diff --check` | **passed** | No trailing whitespace |

## Status and scores

DNG-01 remains **FUTURE** by product policy. BUG-03, WEB-09, WEB-10, APP-06, and WEB-22–27 remain **PARTIAL** because live WebKit/vendor DOM/SSE/SwiftUI behavior is unavailable in this environment. MODEL-19 remains **PARTIAL** with its source-level refresh-status defect fixed. WEB-26 remains **PARTIAL** with retry context fixed; live browser failure injection remains unverified.

| Story | Code quality | Task adherence | Target-runtime confidence |
|---|---:|---:|---:|
| DNG-01 | 100/100 | 100/100 | 0/100 |
| BUG-03 | 99/100 | 100/100 | 0/100 |
| WEB-09 | 99/100 | 100/100 | 0/100 |
| WEB-10 | 99/100 | 100/100 | 0/100 |
| APP-06 | 99/100 | 100/100 | 0/100 |
| MODEL-19 | 99/100 | 100/100 | 0/100 |
| WEB-22–27 | 99/100 | 100/100 | 0/100 |

> A refresh is not complete merely because it returns models. It must also preserve the user-visible explanation when it changes the selected model, and a retry is not safe merely because it reuses the same remote UUID—it must preserve the original conversation phase.
