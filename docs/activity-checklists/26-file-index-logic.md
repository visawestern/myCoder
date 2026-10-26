# Activity 26 — File Index Logic

## Audit objective

This round audits **STO-06 File Index Logic** from project discovery and the `@` file suggestion path through `ProjectFileScanner`, `ProjectFileIndexLogic`, `FileIndexRecord`, `ProjectFileIndexPersistenceLogic`, `ProjectFileIndexStore`, watcher invalidation, and downstream context construction.

The existing chain correctly scans project-relative files, applies default/gitignore exclusions, hashes content, computes hash/mtime deltas, persists per-project JSON snapshots, and reloads them after cache expiry. The confirmed adversarial defect was that both `ProjectFileIndexLogic.computeDelta` and `ProjectFileIndexPersistenceLogic.applyDelta` used `Dictionary(uniqueKeysWithValues:)`. A duplicate path in a malformed or manually edited snapshot could crash the index refresh instead of recovering deterministically.

## Function and action checklist

| # | UI control/action/function | Chain traced | Expected behavior | Result |
|---:|---|---|---|---|
| 1 | Project/workspace selection | workspace open → project path → index cache/store | Index records must be scoped to the active project, not another workspace. | **Pass by source/tests; native workspace runtime UNVERIFIED.** |
| 2 | `@` file trigger | `InputCommandTriggerLogic` → `inputDropdownContext` → file source | Show file suggestions for the active project and preserve the existing input flow. | **Pass by existing input tests; native UI UNVERIFIED.** |
| 3 | Recursive scan | `ProjectFileScanner.scan` → `FileIndexRecord` | Walk regular files recursively and skip unreadable entries without crashing. | **Pass by scanner tests.** |
| 4 | Relative path construction | `relativePath(of:from:)` | Store project-relative paths, not absolute paths, for portability and privacy. | **Pass by source.** |
| 5 | Default exclusions | scanner → `shouldExclude` | Exclude `.git`, `.mycoder`, dependency/build/cache directories, and other configured defaults. | **Pass by existing logic tests.** |
| 6 | Gitignore patterns | scanner → `matchesGitignore` | Honor exact segments, directory patterns, and extension patterns. | **Pass by existing tests; full gitignore grammar remains intentionally simplified.** |
| 7 | Size cap | scanner → `shouldIndex` | Skip files larger than configured max size; index supported zero/normal-size files. | **Pass by existing tests.** |
| 8 | Content hash | scanner → `hash(of:)` | Produce deterministic content identity across repeated scans and platform fallback. | **Pass by scanner tests; CryptoKit vs Linux fallback are not cross-verified byte-for-byte.** |
| 9 | Language inference | extension → `language(forExtension:)` | Assign stable display tags and a safe text fallback. | **Pass by existing tests.** |
| 10 | Delta unchanged file | `computeDelta` current/scanned | Do not re-index a file when hash and mtime are unchanged. | **Pass by existing tests.** |
| 11 | Delta changed/new file | `computeDelta` | Upsert changed or newly discovered files. | **Pass by existing tests.** |
| 12 | Delta removed file | `computeDelta` | Return paths absent from the fresh scan for removal. | **Pass by existing tests.** |
| 13 | Duplicate current/scanned paths | malformed snapshot/scanner input → map construction | Collapse duplicate paths deterministically, with the last record winning, and never trap. | **Fixed and tested in Round 72.** |
| 14 | Persistent apply delta | snapshot load → `applyDelta` → store save | Apply upserts/removals and return deterministic path-sorted records. | **Fixed and tested for duplicate paths.** |
| 15 | Snapshot encode/decode | `ProjectFileIndexPersistenceLogic` → JSON | Preserve project path and records across relaunch. | **Pass by persistence tests; file I/O UNVERIFIED.** |
| 16 | Snapshot project isolation | `ProjectFileIndexStore.load` | Reject a snapshot whose embedded path does not equal the requested project path. | **Pass by source.** |
| 17 | Atomic save | store → `.mycoder/file_index.json` | Create project metadata directory and atomically write the snapshot. | **Pass by source; macOS file permissions UNVERIFIED.** |
| 18 | Index refresh settings | `IndexingSettingsView` → `IndexingSettingsLogic` | Do not claim unavailable automatic indexing; disclose on-demand behavior. | **Pass by Round 60 source/tests; native UI UNVERIFIED.** |
| 19 | FSEvents invalidation | project lifecycle → watcher → cache invalidation | Invalidate only the active project after debounce and generation checks. | **PARTIAL:** source/pure watcher contracts pass; live macOS events UNVERIFIED. |
| 20 | Persistent FTS search | index records → SQLite FTS consumer | Provide large-project full-text search rather than synchronous rescan. | **MISSING:** intentionally separate unresolved IDX-03 capability. |

## Confirmed defect and TDD evidence

### Duplicate index paths crashed refresh

`computeDelta` and `applyDelta` both constructed dictionaries with `Dictionary(uniqueKeysWithValues:)`. Although the normal scanner emits unique relative paths, persisted JSON is an external boundary and could contain duplicates. Any duplicate path caused a fatal runtime trap during refresh/relaunch.

`ProjectFileIndexDuplicateRecordTests` was written first. The corrected red run reached the intended fatal duplicate-key crash in the Foundation harness. The green fix adds `ProjectFileIndexLogic.recordsByPath`, uses deterministic last-record-wins deduplication, iterates scanned paths in sorted order, and applies the same helper to persistence. Both delta methods now recover without a crash and return deterministic results.

## Remaining limitations

STO-06 remains **PARTIAL**. Persistent JSON indexing, delta computation, project isolation, and the duplicate-path crash are covered. CoreServices watcher behavior is implemented but macOS runtime-unverified. Full persistent SQLite/FTS search remains missing and is tracked separately as IDX-03; this round does not falsely claim that JSON snapshots constitute FTS.

## Evidence and scores

| Check | Result | Boundary |
|---|---:|---|
| Red duplicate-path regression | **failed as expected** | Production dictionary trap reached in harness |
| Green duplicate-path regressions | **2/2 passed** | `computeDelta` and `applyDelta` recover deterministically |
| Full Foundation harness | **242/242 passed** | Existing contracts plus STO-06 regressions |
| Swift parser validation | **passed** | Record, logic, persistence sources |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| macOS file I/O/FSEvents | **UNVERIFIED/PARTIAL** | Requires native runtime |
| Persistent SQLite/FTS | **MISSING** | Separate IDX-03 capability |

The **implementation quality score is 94/100**. Malformed duplicate snapshots no longer crash index refresh and output order is deterministic; FTS, native file I/O, and live watcher behavior remain.

The **task-following score is 100/100**. Every STO-06 function and action was traced, the confirmed crash received a red regression before the fix, and missing/runtime-only behavior remains honestly classified.

> A persisted index is an untrusted boundary: duplicate paths must be recoverable data, not a reason to terminate the refresh process.
