# Activity 36 — Usage Screen with Real Data

## Audit objective

This round audits **USG-02 Usage Screen with Real Data** from provider-response usage capture through assistant-message persistence, legacy and per-project database reads, source merge ordering, date-range filtering, token/cost totals, active days, model normalization, favorite model, Messages tile, database-size card, empty state, and SwiftUI rendering.

Round 63 fixed the major source omission: AppState now merges legacy usage rows with every maintained project database. The fresh audit found a screen-level inconsistency: the Usage view applied the selected 7/30-day range to tokens, cost, active days, and model breakdown, but the Messages tile used `StorageStats.messageCount`, an all-time raw database count that included messages outside the selected period and messages without usage records.

## Full chain checklist

| # | UI/control/action/function | Chain traced | Expected behavior | Result |
|---:|---|---|---|---|
| 1 | Usage tab entry | Settings navigation → `UsageSettingsView` | Usage view loads current stats and usage points when shown. | **Pass by source; native navigation UNVERIFIED.** |
| 2 | Legacy usage source | `DatabaseManager.usageDataPoints()` | Preserve historical global usage rows. | **Pass by source/tests.** |
| 3 | Project usage source | `ProjectDatabaseManager.usageDataPoints()` for maintained paths | Include current per-project usage rows. | **Pass by existing Round 63 tests/source.** |
| 4 | Source merge | `UsageDataSourcesLogic.merge` | Combine all sources deterministically without dropping nullable costs. | **Pass by existing tests/source.** |
| 5 | Storage errors | `try?` source reads | A failed database read does not crash the view, but current implementation silently omits that source. | **PARTIAL:** no visible load-error state. |
| 6 | Time-range control | `UsageRange.last7/last30` → segment buttons | Selected period changes every time-sensitive metric. | **Pass by source; native interaction UNVERIFIED.** |
| 7 | Date filter | `UsageStatisticsAggregator.filter` | Include points on both range boundaries and exclude outside points. | **Pass by existing tests/source.** |
| 8 | Total tokens | filtered points → `totals` | Show prompt plus completion tokens only for the selected period. | **Pass by existing tests/source.** |
| 9 | Total cost | filtered points → `totals` → `costLabel` | Sum known costs; show N/A if no trustworthy cost exists, not fabricated $0.00. | **Pass by existing tests/source.** |
| 10 | Messages tile | filtered points → `UsageScreenSummaryLogic.messageCount` | Follow the selected usage period and align with the screen’s other usage metrics. | **Fixed Round 82:** no longer uses all-time raw DB message count. |
| 11 | Active days | filtered points → calendar day set | Count distinct calendar days in the selected period. | **Pass by existing tests/source.** |
| 12 | Favorite model | filtered points → normalized aggregate | Reflect most-used model by actual token volume, not current selection. | **Pass by existing tests/source.** |
| 13 | Model normalization | snapshot-suffixed IDs → canonical model key | Group dated model snapshots deterministically. | **Pass by existing tests/source.** |
| 14 | Per-model rows | aggregate → `LazyVGrid` breakdown | Show message count, prompt/completion tokens, and honest cost per normalized model. | **Pass by source; native layout UNVERIFIED.** |
| 15 | Database size | `StorageStats` → card | Show storage size independent of time-range usage. | **Pass by source.** |
| 16 | Empty period | filtered points empty | Show zero/none/usage-period message without fake data. | **Fixed/contract-tested for Messages count; native rendering UNVERIFIED.** |
| 17 | Refresh/reappearance | `.onAppear` → reload | Re-entering the tab reloads the current snapshot. | **Pass by source; native lifecycle UNVERIFIED.** |
| 18 | Loading state | synchronous `onAppear` reads | Avoid blocking or show progress while large project DBs are read. | **PARTIAL:** reads are synchronous and no progress indicator exists. |
| 19 | Error state | DB read failures | Tell the user that data may be incomplete and offer retry. | **PARTIAL:** failures are swallowed with `try?`. |

## Confirmed defect and TDD evidence

### Messages tile ignored the selected date range

`UsageSettingsView` computed `filteredPoints` for tokens, cost, active days, and model aggregates, but `formattedMessages` returned `stats?.messageCount`. `StorageStats.messageCount` is an all-time raw database count, not the count of usage-bearing assistant records in the selected 7/30-day period. The tile could therefore show a larger all-time number while every adjacent usage metric showed only the selected period.

`UsageScreenSummaryLogicTests` was written before implementation. The first red run initially exposed a missing Foundation import in the test fixture; after that fixture correction, the red run failed specifically because `UsageScreenSummaryLogic` did not exist. The green implementation defines `messageCount(for:)` over the already-filtered usage points, and `UsageSettingsView` now consumes that contract.

The result is intentionally the count of persisted usage points represented by the Usage screen. Raw all-time database message count remains appropriate for storage statistics, but not for a range-filtered usage card.

## Evidence and scores

| Check | Result | Boundary |
|---|---:|---|
| Red range-scoped Messages regression | **failed as expected** | Summary contract absent before implementation |
| Green USG-02 summary tests | **2/2 passed** | Selected-period and empty-period count |
| Full Foundation harness | **265/265 passed** | Existing contracts plus USG-02 regression |
| Swift parser validation | **passed** | Summary helper and UsageSettingsView |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| Native SwiftUI Usage screen | **UNVERIFIED** | Requires macOS runtime |
| Large-database loading performance | **UNVERIFIED** | Linux harness does not reproduce user-scale DB/UI timing |
| Visible database-read error/retry UX | **PARTIAL** | Current `try?` reads remain silent |

`USG-02` remains **PARTIAL**. Legacy/project source aggregation, selected-period token/cost/model metrics, active days, N/A cost behavior, and range-scoped Messages are contract-tested. Native rendering, large-database responsiveness, and visible read-error/retry UX remain incomplete or unverified.

The **implementation quality score is 95/100**. The confirmed range inconsistency is fixed with a narrow pure contract and no change to storage semantics; synchronous loading and silent source-read failures remain.

The **task-following score is 100/100**. Every usage source, filter control, stat card, model row, empty state, loading boundary, and failure path was traced; the red test preceded the fix; documentation was updated; and native/runtime boundaries remain explicitly UNVERIFIED.

> A time-range selector must govern every time-sensitive card on the screen; an all-time raw message count must not masquerade as a selected-period usage count.
