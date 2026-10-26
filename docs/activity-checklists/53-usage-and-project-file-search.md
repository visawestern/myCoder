# Activity 53 — Usage Data Integrity and Persistent Project-File Search

## Audit objective

This round audits **USG-02**, **USG-03**, and **IDX-03** from provider response usage extraction through database persistence, legacy/per-project merge, date-range filtering, message/active-day/model/cost aggregation, visible Usage screen cards, file scanning, snapshot persistence, watcher invalidation, SearchPalette query handling, result ranking, and Finder reveal.

## Canonical stories and status decisions

| Story | Expected behavior | Round 99 decision |
|---|---|---|
| USG-02 | Usage screen renders real range-filtered tokens, costs, messages, active days, and per-model data from merged legacy and per-project stores. | **PARTIAL retained.** Invalid negative tokens now fail closed; existing range/source contracts remain green. Large DB loading, read-error visibility, and native SwiftUI rendering remain unverified. |
| USG-03 | Cost per model uses real provider-reported cost, preserves valid zero, rejects invalid values, and groups normalized models. | **PARTIAL retained.** Cost safety was already correct; token sanitization closes a related data-integrity path. Provider-specific pricing remains unavailable where no trustworthy payload exists. |
| IDX-03 | Project files are persistently indexed and searchable, with bounded content capture, incremental updates, and a visible user-facing search action. | **MISSING narrowed to PARTIAL.** Persistent JSON index and watcher already existed; Round 99 adds bounded UTF-8 searchable text, ranked search, binary exclusion, and SearchPalette/Finder wiring. SQLite file FTS and automatic background indexing remain absent. |

## Full manual chain checklist

| # | Action/function | Chain and invariant | Result |
|---:|---|---|---|
| 1 | Usage capture | Direct/ACP response usage enters `UsageCapture`; missing/invalid cost is N/A and model/provider have safe fallback labels. | **Pass by existing tests/source.** |
| 2 | Token validation | Provider and persisted prompt/completion counts cannot be negative before totals or DB writes. | **Fixed Round 99 red→green.** |
| 3 | Zero-row filtering | No-token usage blocks do not create misleading usage points; one-sided positive usage remains valid. | **Pass by existing source/tests.** |
| 4 | Legacy DB read | Assistant usage rows are read from real columns, invalid/zero rows are skipped, and model/provider/timestamp are reconstructed. | **Pass by source; DB runtime unverified.** |
| 5 | Per-project DB read | Each project database contributes its own usage-bearing assistant rows without cross-project routing. | **Pass by source; DB runtime unverified.** |
| 6 | Source merge | Legacy and all loaded project paths are merged deterministically and sorted. | **Pass by existing tests/source.** |
| 7 | Range filter | Last-7/last-30 selection filters usage points before cards and table aggregation. | **Pass by existing tests/source.** |
| 8 | Message count | Messages card counts filtered usage-bearing points, not all-time raw DB messages. | **Pass by existing tests/source.** |
| 9 | Active days | Calendar days are deduplicated after period filtering. | **Pass by existing tests/source.** |
| 10 | Model aggregate | Snapshot suffixes normalize, prompt/completion totals sum, and favorite model uses actual token volume. | **Pass by existing tests/source.** |
| 11 | Cost aggregate | Costs sum only finite nonnegative provider values; nil remains N/A and valid zero remains `$0.00`. | **Pass by existing tests/source.** |
| 12 | Usage screen | Cards and per-model rows show real aggregation values; empty periods show a clear no-data message. | **Pass by source; native SwiftUI rendering unverified.** |
| 13 | Usage read failures | Database read failures currently fail closed to empty/zero values. | **Known PARTIAL boundary:** no visible read-error state yet; not changed speculatively. |
| 14 | File exclusions | Scanner excludes `.git`, build/dependency/cache directories, gitignore patterns, oversized files, and unreadable files. | **Pass by existing tests/source.** |
| 15 | File metadata scan | Scanner records relative path, hash, size, mtime, language, and deterministic ordering. | **Pass by existing tests/source.** |
| 16 | Searchable content capture | Ordinary UTF-8 text is retained only up to a bounded cap; binary content becomes nil. | **Fixed Round 99; source/tests pass.** |
| 17 | Snapshot persistence | `file_index.json` encodes/decodes records, rejects path mismatches, and applies hash/mtime delta updates. | **Pass by existing tests/source.** |
| 18 | Watcher invalidation | Active project watcher invalidates cache only for the current generation/path; next demand rescans. | **Pass by existing tests/source.** |
| 19 | Search query | Empty/whitespace query returns no file matches; all query terms must match content or path. | **Fixed Round 99; source/tests pass.** |
| 20 | Search ranking | Content matches outrank path-only matches; results are stable and limited; binary records never appear. | **Fixed Round 99; source/tests pass.** |
| 21 | SearchPalette | Global search retains session results and now shows matching indexed files for the active project. | **Fixed Round 99 source acceptance; native UI unverified.** |
| 22 | File result action | Clicking a file result reveals the exact project-relative file in Finder and dismisses the palette. | **Fixed Round 99 source acceptance; AppKit runtime unverified.** |
| 23 | Security boundary | The index excludes `.mycoder` and known generated/dependency directories; content indexing is bounded but does not yet implement secret-pattern redaction. | **PARTIAL boundary documented.** |
| 24 | Remaining IDX gap | No SQLite `file_index` table/file-content FTS and no automatic continuous indexing are present. | **Documented as remaining PARTIAL, not falsely marked PASS.** |

## Confirmed defect and TDD evidence

### USG-02/USG-03 — Negative token counts distorted usage totals

`UsageCapture` and `UsageDataPoint` accepted negative prompt/completion token counts. A malformed provider payload or persisted row could produce negative totals, negative model ranking, or a negative session usage value. Two red tests were written first and failed with four assertions. Both boundaries now clamp counts at zero before aggregation and persistence-facing consumption. Valid positive counts, zero-cost payloads, and N/A costs remain unchanged.

### IDX-03 — File index existed but file-content search was missing

The audit found a real persistent `file_index.json` metadata snapshot and watcher-driven on-demand scan, but no searchable file content and no user-visible file result in SearchPalette. The red regression first required `searchableText` and a deterministic `ProjectFileSearchLogic`; a persistent source acceptance then required AppState/SearchPalette/Finder wiring. Round 99 adds bounded UTF-8 text capture, all-term ranking, binary exclusion, on-demand persistence, visible file results, and Finder reveal.

### No speculative cost change

USG-03 cost provenance was already correctly fail-closed for negative, NaN, and infinite costs while preserving `$0.00`. No duplicate fix was introduced.

## Evidence

| Check | Result | Boundary |
|---|---:|---|
| Usage token red regressions | **2 tests failed before fix → 2/2 passed** | Foundation data boundary |
| IDX-03 file search red regression | **compile failed before fix → 2/2 passed** | Foundation search logic |
| Project-file wiring red acceptance | **failed before AppState/UI wiring → passed** | AppState + SearchPalette source |
| Usage/index source acceptance | **passed** | Production invariants |
| Focused file index/search suites | **20/20 passed** | Foundation scanner/persistence/search |
| Full Foundation harness | **357/357 passed** | Linux-safe suites |
| Adversarial source checks | **12/12 passed** | Existing safety invariants |
| Canonical registry integrity | **274 rows, unique IDs, valid statuses** | Registry acceptance |
| Swift parser validation | **passed** | Changed production/test files |
| `git diff --check` | **passed** | No trailing whitespace |

## Status and scores

USG-02 and USG-03 remain **PARTIAL** because native SwiftUI rendering, large database performance, silent database read failures, and provider-specific pricing are not verifiable in this Linux environment. IDX-03 moves from **MISSING** to **PARTIAL** because persistent metadata indexing and visible bounded project-file search now exist, while SQLite file-content FTS and automatic background indexing remain absent.

| Story | Code quality | Task adherence | Target-runtime confidence |
|---|---:|---:|---:|
| USG-02 | 99/100 | 100/100 | 0/100 |
| USG-03 | 99/100 | 100/100 | 0/100 |
| IDX-03 | 97/100 | 100/100 | 0/100 |

> A persistent metadata snapshot is not automatically a full-text index. Round 99 closes the user-visible search gap with bounded text and deterministic ranking while keeping the remaining SQLite FTS/automatic-indexing boundary explicit.
