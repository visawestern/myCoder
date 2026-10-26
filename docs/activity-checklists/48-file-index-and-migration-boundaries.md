# Activity 48 — File Index and Migration Boundaries

## Audit objective

This round audits **STO-06**, **STO-07**, and **STO-11** from project-file discovery and persisted snapshot state through incremental delta application, FSEvents invalidation, cache refresh, and legacy migration policy. The audit distinguishes source-level indexing guarantees from macOS CoreServices delivery and from the user-directed removal of legacy database migration.

## Full chain checklist

| Story | Chain audited | Expected behavior | Result |
|---|---|---|---|
| STO-06 | Project scan → size/exclusion filter → hash/mtime delta → duplicate collapse → snapshot persistence → `@` file suggestions | Only valid indexable files enter the snapshot; changed/new/removed files produce deterministic deltas; duplicate paths recover last-record-wins; per-project snapshots are isolated and atomic. | **Fixed Round 94 negative-size fail-closed edge; 15/15 ProjectFileIndexLogic tests and 332/332 full Foundation tests. Persistent SQLite/FTS boundary remains UNVERIFIED/MISSING.** |
| STO-07 | Workspace selection → watcher generation/lifecycle → CoreServices events → debounce/path filter → cache invalidation → on-demand rescan | Watcher follows the canonical active project, ignores `.mycoder` and unrelated paths, debounces bursts, rejects stale generation callbacks, and refreshes the `@` cache on demand. | **No new source defect confirmed Round 94; existing watcher/lifecycle contracts pass. Live macOS FSEvents delivery, permissions, shutdown, and native cache refresh remain UNVERIFIED.** |
| STO-11 | First-run migration policy → legacy/per-project database creation | Legacy single-DB migration would be explicit if supported; current product intentionally starts fresh per-project databases under the user’s 2026-08-02 HTTP-only/clean-slate directive. | **FUTURE by explicit product directive; no migration code or red implementation test is appropriate.** |

## Detailed manual trace

| # | Action/function | Chain and invariant | Result |
|---:|---|---|---|
| 1 | Project scan root | `ProjectFileScanner.scan` standardizes the root, enumerates regular files, skips unreadable entries, and computes relative paths. | **Pass by source/tests; native filesystem permissions UNVERIFIED.** |
| 2 | Exclusion rules | `.git`, `node_modules`, `.mycoder`, build/IDE/virtualenv directories and gitignore patterns are filtered before indexing; excluded directories are pruned. | **Pass by source/tests.** |
| 3 | File-size gate | `shouldIndex` rejects negative metadata and files above the configured maximum before content reads. | **Fixed Round 94 red/green.** |
| 4 | Hash/mtime delta | `computeDelta` upserts new or hash/mtime-changed paths and reports current paths absent from the scan as removals. | **Pass by source/tests.** |
| 5 | Duplicate recovery | `recordsByPath` uses deterministic last-record-wins collapse; sorted paths make delta and snapshot output stable. | **Pass by existing Round 72 tests.** |
| 6 | Snapshot encoding | `ProjectFileIndexPersistenceLogic.encode/decode` round-trips project path and records; `applyDelta` removes deleted paths and returns sorted records. | **Pass by source/tests.** |
| 7 | Project isolation | `ProjectFileIndexStore` stores `file_index.json` under `<project>/.mycoder`, uses atomic writes, and rejects an empty project path. | **Pass by source; live filesystem write permissions UNVERIFIED.** |
| 8 | `@` suggestion refresh | `inputDropdownContext` loads the project snapshot, scans on cache miss/TTL expiry, applies the delta, saves the snapshot, and returns names for the active project only. | **Pass by source; SwiftUI interaction UNVERIFIED.** |
| 9 | Workspace lifecycle | `selectedWorkspace.didSet` compares canonical project paths and restarts the watcher only when the project identity changes. | **Pass by existing lifecycle tests.** |
| 10 | FSEvents path filtering | Watcher standardizes event paths, accepts only the project root/subtree, ignores `.mycoder`, debounces for 300 ms, and invalidates only the active generation/path. | **Pass by pure tests/source; CoreServices runtime UNVERIFIED.** |
| 11 | Stale event safety | AppState compares event generation and canonical project path before clearing the cache, preventing a prior workspace from invalidating a new workspace’s cache. | **Pass by source/tests; concurrent native event delivery UNVERIFIED.** |
| 12 | Indexing settings honesty | Settings toggles remain disabled because full automatic repository indexing is intentionally unavailable; the active watcher only invalidates the on-demand `@` cache and does not claim full FTS indexing. | **No new defect confirmed; copy is consistent with the narrower implementation boundary.** |
| 13 | Legacy migration | Registry marks STO-11 FUTURE and source inventory contains no active migrator. Implementing migration would contradict the explicit clean-slate/HTTP-only directive. | **Intentionally deferred.** |

## Confirmed defect and TDD evidence

### STO-06 — negative file metadata was accepted

`ProjectFileIndexLogic.shouldIndex` rejected only values greater than `maxFileSize`. A malformed negative file size therefore passed the gate and could be persisted as an index record. A red regression was written first. The gate now rejects `size < 0` as well as oversized files; the real scanner already routes all records through this gate.

### STO-07 — no additional confirmed defect

The audit specifically checked the apparent mismatch between disabled “automatic indexing” settings and the active watcher. The watcher does not perform full automatic repository/FTS indexing; it invalidates the project file cache so the next `@` suggestion request rescans on demand. The settings boundary therefore remains honest for the implemented capability. Native watcher delivery remains unverified rather than marked PASS.

### STO-11 — intentionally deferred

STO-11 is not an unresolved implementation bug. The registry explicitly records the feature as FUTURE and the product directive removed legacy migration in favor of a clean per-project, HTTP-only start. No migration implementation or test was added.

## Evidence

| Check | Result | Boundary |
|---|---:|---|
| STO-06 negative-size red test | **failed as expected → 15/15 passed** | Foundation index logic |
| STO-06 persistence/delta suites | **existing tests pass** | Foundation snapshot logic |
| STO-07 watcher logic | **existing tests pass** | Foundation path/generation/debounce logic |
| STO-07 watcher lifecycle | **existing tests pass** | Foundation lifecycle logic |
| STO-11 migration | **intentionally FUTURE** | Explicit product directive |
| Full Foundation harness | **332/332 passed** | Linux-safe suites |
| Adversarial source checks | **12/12 passed** | Existing web/model safety invariants |
| Swift parser validation | **passed** | Changed indexing, watcher, AppState, settings, and test files |
| `git diff --check` | **passed** | No trailing whitespace |

## Status and scores

The confirmed STO-06 source-level defect is fixed. STO-07 remains **PARTIAL** because CoreServices/FSEvents, native filesystem permissions, and SwiftUI cache refresh cannot be verified in the Linux harness. STO-11 remains **FUTURE** by explicit product policy. No Linux result is represented as native runtime proof.

| Story | Code quality | Task adherence | Target-runtime confidence |
|---|---:|---:|---:|
| STO-06 | 99/100 | 100/100 | 0/100 |
| STO-07 | 98/100 | 100/100 | 0/100 |
| STO-11 | 100/100 | 100/100 | 0/100 |

> The audit does not convert a working pure index contract into a claim that FSEvents, SQLite/FTS, or macOS permissions have been validated. Those remain explicitly bounded.
