# Activity 37 — Cost per Model

## Audit objective

This round audits **USG-03 Cost per Model** from provider response metadata through
`UsageCapture`, assistant-message mutation, legacy and per-project SQLite persistence,
`UsageDataPoint` reconstruction, source merging, model normalization, cost aggregation,
cost-label rendering, and the per-model Usage screen. Every provider branch is traced
and native macOS/WebKit/live-provider boundaries are stated explicitly.

Round 63 fixed the major source omission: project-scoped usage rows now reach
aggregation. Round 83 found a second defect: provider-reported negative, NaN, or
infinite cost values were persisted and rendered as monetary charges. Valid zero cost
must remain a distinct, displayable value.

## Full chain checklist

| # | UI/control/action/function | Chain traced | Expected behavior | Result |
|---:|---|---|---|---|
| 1 | Settings → Usage tab | Settings navigation → `UsageSettingsView` | Usage view loads current stats and usage points when shown. | **Pass by source; native navigation UNVERIFIED.** |
| 2 | Last 7 / Last 30 days | `UsageRange` segment buttons → `filteredPoints` | Every time-sensitive metric uses the selected period. | **Pass by source; native interaction UNVERIFIED.** |
| 3 | Usage source loading | `AppState.loadUsageDataPoints()` | Load legacy and every maintained project source. | **Pass by source and existing tests.** |
| 4 | Legacy database read | `DatabaseManager.usageDataPoints()` | Reconstruct assistant rows with timestamp, model, provider, tokens, nullable cost. | **Pass by source.** |
| 5 | Project database read | `ProjectDatabaseManager.usageDataPoints()` | Reconstruct project-scoped rows with same schema and nullable cost. | **Pass by source.** |
| 6 | Cross-source merge | `UsageDataSourcesLogic.merge` | Combine legacy and project rows deterministically, preserving nil cost. | **Pass by existing tests/source.** |
| 7 | Direct provider send | `DirectChatClient.send` → `parseResponse` | Parse assistant text and optional usage without fabricating missing price. | **Pass by source; live payload UNVERIFIED.** |
| 8 | Direct cost keys | `extractUsage` → `usage.cost_usd` or `usage.cost` | Accept provider-reported numeric/string cost; nil when absent. | **Pass by source.** |
| 9 | Direct token gate | `extractUsage` prompt/completion token check | Skip usage block with no token accounting. | **Pass by source.** |
| 10 | Direct model/provider identity | response `model` + `usage.provider_id` fallback `direct` | Model and provider IDs are not empty in the persisted capture. | **Pass by source.** |
| 11 | ACP provider send | `ACPClient.sendChatCompletion` → `response.usage` → `UsageCapture(acpUsage:)` | ACP carries no cost; costUSD is always nil for this path. | **Pass by source; live ACP payload UNVERIFIED.** |
| 12 | Auto Free provider send | `MyCoderAutoFreeStore.streamChat` → streamed chunks | No usage block; no cost; no token accounting. | **Pass by source — no UsageCapture is created.** |
| 13 | Web provider send | `WebChatDriver` → browser turn | No usage block; no cost; no token accounting. | **Pass by source — no UsageCapture is created.** |
| 14 | Serve provider send | MiMo Serve SSE stream | Serve carries no cost payload in the traced chain. | **Pass by source — no UsageCapture is created.** |
| 15 | Negative cost sanitization | `UsageCostSafety.sanitized` in `UsageCapture.init` and `UsageDataPoint.init` | Negative provider cost becomes nil (N/A), not a negative charge. | **Fixed Round 83; tested by `UsageCostSafetyTests`.** |
| 16 | NaN/infinite cost sanitization | `UsageCostSafety.sanitized` | NaN or infinite provider cost becomes nil (N/A), not `$nan`/`$inf`. | **Fixed Round 83; tested by `UsageCostSafetyTests`.** |
| 17 | Zero cost preservation | `UsageCostSafety.sanitized` | Zero cost is a valid reported charge and renders as `$0.00`. | **Pass; tested by `UsageCostSafetyTests`.** |
| 18 | Cost label nil → N/A | `UsageStatisticsAggregator.costLabel(nil)` | Nil cost renders as `N/A`, not `$0.00`. | **Pass by existing tests.** |
| 19 | Cost label non-finite input | `costLabel(.infinity)`, `costLabel(-1)` | Non-finite or negative direct inputs render as `N/A`. | **Fixed Round 83; tested by `UsageCostSafetyTests`.** |
| 20 | Model normalization | `normalizeModelName` strips snapshot suffix | `gpt-4o-2024-08-06` and `gpt-4o` aggregate together. | **Pass by existing tests.** |
| 21 | Per-model aggregation | `aggregateByModel` groups normalized keys | Message count, tokens, and cost are summed per normalized model. | **Pass by existing tests.** |
| 22 | Mixed nil/non-nil cost aggregation | aggregate loop: `(agg.costUSD ?? 0) + cost` | Points without cost do not contribute to the model's cost total. | **Pass by existing tests.** |
| 23 | Total cost | `totals` → `compactMap(\.costUSD)` | Total cost is nil when no point has a cost; partial sum when some do. | **Pass by existing tests.** |
| 24 | Per-model row rendering | `ForEach(byModel)` → `costLabel(agg.costUSD)` | Each model row shows honest cost or N/A. | **Pass by source; native layout UNVERIFIED.** |
| 25 | Empty period | `byModel.isEmpty` | Show usage-period message without fake data. | **Pass by source; native rendering UNVERIFIED.** |
| 26 | Database read failures | `try?` source reads | A failed read does not crash the view; source is silently omitted. | **PARTIAL:** no visible load-error state. |
| 27 | Refresh/reappearance | `.onAppear` → reload | Re-entering the tab reloads the current snapshot. | **Pass by source; native lifecycle UNVERIFIED.** |

## Confirmed defects and TDD evidence

### Defect 1 — Negative provider cost rendered as a charge

`UsageCapture.init` stored `costUSD` verbatim. A provider that reported
`"cost_usd": -0.25` would persist and display `$-0.25`. The `costLabel` formatter
also accepted negative direct inputs and produced `$-1.00`.

### Defect 2 — Non-finite provider cost rendered as a charge

`NaN` and infinite values passed through the same path and produced `$nan` or `$inf`
in the per-model cost column.

### Fix — `UsageCostSafety.sanitized`

A single `UsageCostSafety.sanitized` helper was introduced in
`UsageStatisticsAggregator.swift`. It returns nil for any input that is absent,
non-finite, or negative, and returns the original value otherwise. The helper is
applied in three places:

1. `UsageCapture.init` — at capture time, before persistence.
2. `UsageDataPoint.init` — at reconstruction time, after database read.
3. `UsageStatisticsAggregator.costLabel` — at display time, as a final defensive gate.

Zero cost is explicitly preserved: `sanitized(0) == 0`, so a provider that reports a
genuinely free call renders `$0.00` rather than `N/A`.

### TDD sequence

Red tests were written first in `UsageCostSafetyTests.swift` before any production
change. The first red run confirmed the missing invariant: `point.costUSD → -0.25`
instead of `nil`, and `costLabel → "$nan"` instead of `"N/A"`. After the
`UsageCostSafety` helper was introduced and wired into all three sites, the five tests
passed and the full 270-test Foundation harness remained green.

## Evidence

| Check | Result | Boundary |
|---|---:|---|
| Red `UsageCostSafetyTests` run | **failed as expected** | Missing sanitization before implementation |
| Green `UsageCostSafetyTests` (5/5) | **passed** | Negative, NaN, infinite, zero, and nil cases |
| Full Foundation harness | **270/270 passed** | All existing contracts plus USG-03 regressions |
| Swift parser validation | **passed** | `UsageStatisticsAggregator.swift`, `UsageDataPoint.swift`, `UsageCostSafetyTests.swift` |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| `git diff --check` | **passed** | No trailing whitespace |
| Live provider cost payloads | **UNVERIFIED** | Linux harness cannot receive live gateway responses |
| Native SwiftUI per-model rendering | **UNVERIFIED** | Requires macOS runtime |
| Provider-specific pricing tables | **UNVERIFIED** | No pricing data is embedded in the app |

## Scores

| Dimension | Score | Rationale |
|---|---:|---|
| Implementation quality | 97/100 | Cost sanitization is centralized in a single helper applied at all three boundaries; zero cost is correctly preserved; the full harness is green. Synchronous large-DB loading and silent source-read failures remain. |
| Task adherence | 100/100 | Every provider branch was manually traced; red tests preceded the fix; all three sanitization sites were identified and wired; documentation and registry updated; native/runtime boundaries remain explicitly UNVERIFIED. |
| Target-runtime confidence | 0/100 | Linux cannot execute SwiftUI/AppKit or validate live provider/browser usage metadata. |

> A provider-reported cost is data, not an estimate. A negative, NaN, or infinite value
> cannot be presented as a monetary charge; it must be treated as unavailable.
