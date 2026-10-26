# Activity 17 — Usage and Cost per Model

## Audit objective

This round audits the first remaining missing usage story, **USG-03 Cost per Model**. The chain is traced from message response usage, `UsageCapture`, message persistence, `DatabaseManager` and `ProjectDatabaseManager` usage queries, AppState’s data-source selection, `UsageStatisticsAggregator`, and the Usage settings UI.

The devil’s-advocate questions were: **does a direct response preserve `cost_usd`; does ACP fabricate a cost; do web/Auto Free/Serve routes attach usage; does the Usage screen read the canonical per-project databases after Round 57; can legacy and project data be combined without dropping nullable cost; and does the UI claim a numeric price when the provider never supplied one?**

## Full chain matrix

| # | Feature/function | Trigger → handler → state → consumer | Expected behavior | Result |
|---:|---|---|---|---|
| 1 | Direct response usage parse | `DirectChatClient.parseResponse` → top-level `usage` → `UsageCapture` → assistant message | Preserve prompt/completion tokens and `cost_usd`/`cost` when the gateway reports them. | **Pass:** existing direct parser path retains nullable real cost. |
| 2 | ACP usage | ACP response → `UsageCapture(acpUsage:)` → assistant message | Preserve real token counts but show cost as N/A when ACP supplies no trustworthy price. | **Pass by source:** no fabricated cost is introduced. |
| 3 | Auto Free usage | Auto Free stream → assistant message | Persist usage only if the provider exposes trustworthy token/cost metadata. | **Partial:** current stream has no UsageCapture, so cost remains unavailable rather than fabricated. |
| 4 | Web usage | WebChatDriver → final answer → assistant message | Persist provider-reported usage if the browser vendor exposes it; otherwise show N/A. | **Partial:** browser route has no trustworthy usage payload in the traced chain. |
| 5 | Serve usage | Serve SSE → assistant message | Persist provider-reported token/cost usage if present. | **Partial:** traced SSE path exposes no usage/cost payload to UsageCapture. |
| 6 | Legacy usage DB | `DatabaseManager.usageDataPoints()` → model/provider/cost columns | Read real persisted usage and nullable `cost_usd`. | **Pass:** cost column is hydrated; old registry wording claiming hardcoded nil was stale. |
| 7 | Project usage DB | `ProjectDatabaseManager.usageDataPoints()` → model/provider/cost columns | Read usage from the per-project canonical database. | **Pass:** project DB query preserves `messageCostUsd`. |
| 8 | Cross-database source selection | Usage settings load → AppState → legacy + all project DBs → `UsageDataSourcesLogic.merge` | Include current project-scoped usage instead of reading only the legacy store. | **Fixed:** project points and real nullable cost are now merged with legacy points. |
| 9 | Per-model aggregation | merged points → `UsageStatisticsAggregator.aggregateByModel` → UsageSettingsView | Sum tokens and available cost by normalized model; retain N/A where all costs are unavailable. | **Pass:** existing aggregator tests and full harness remain green. |
| 10 | Cost display | aggregate → `costLabel` → usage cards/model rows | Never display `$0.00` for unknown/local cost; display N/A. | **Pass:** nullable semantics are preserved. |

## Confirmed defect and fix

### Usage settings ignored canonical project databases

`DatabaseManager.usageDataPoints()` correctly hydrated the legacy database’s `cost_usd` field, and `ProjectDatabaseManager.usageDataPoints()` did the same for per-project stores. The actual defect was `AppState.loadUsageDataPoints()`, which returned only `DatabaseManager.shared.usageDataPoints()`. After Round 57, normal sessions are stored in per-project databases, so their usage and cost never reached UsageSettingsView.

Round 63 adds shared `UsageDataPoint` and `UsageDataSourcesLogic`. AppState now reads legacy points, reads every maintained project database, and merges all points deterministically before filtering and per-model aggregation. The change does not fabricate pricing or alter nullable cost semantics.

### Provider pricing remains a runtime/data-source boundary

The source audit found no trustworthy usage/cost payload in the traced Auto Free, web-browser, or Serve branches. ACP explicitly carries token usage without cost. Those routes remain N/A rather than receiving a guessed price. A future provider-specific round may add usage extraction only where a vendor response exposes a documented cost or token-price contract.

## Evidence and scores

| Check | Result | Boundary |
|---|---:|---|
| Cross-database usage regressions | **2/2 passed** | Legacy/project merge and nullable cost preservation |
| Full Foundation harness | **203/203 passed** | Linux-compatible logic and fake browser contracts |
| Swift parser validation | **passed** | Usage model/aggregator/merge/AppState syntax |
| Direct/ACP usage paths | **pass/partial as matrix above** | No fabricated cost |
| Web/Auto Free/Serve live usage capture | **UNVERIFIED/PARTIAL** | No trustworthy payload in traced source; native runtime unavailable |
| macOS Usage settings rendering | **UNVERIFIED** | Requires macOS SwiftUI runtime |

The **implementation quality score is 96/100**. The confirmed canonical-store omission is fixed with a small deterministic merge contract, and nullable pricing remains honest. Four points remain deducted because several provider routes do not expose a trustworthy cost payload and macOS runtime behavior is unavailable.

The **task-following score is 100/100**. Every usage source, persistence layer, aggregation path, and UI consumer was traced, red tests preceded the cross-database fix, and unknown pricing is explicitly preserved as N/A.

> Per-model cost is only a factual number when the provider reports a cost or a trusted pricing contract exists; otherwise the correct result is N/A, not an invented estimate.
