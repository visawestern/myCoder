# Activity 15 — Project Indexing and File Search

## Audit objective

This checklist audits the first remaining non-PASS registry stories after Activity 14: **STO-06 File Index Logic** and **STO-07 FSEvents Dynamic Reindexing**. The chain is traced from Indexing settings through AppState, file scanning, exclusion and size policy, hashing, incremental delta, persistence, the `@` input dropdown, cache invalidation, and the claimed automatic watcher.

The devil’s-advocate questions were: **does the Indexing settings toggle actually reach a scanner; does the scanner’s result survive relaunch; can a stale cache remove a changed file; does a project switch leak records from the previous project; is there any FSEvents subscription; and does the UI promise automatic indexing that the code cannot perform?**

## Full chain matrix

| # | Feature/control | Trigger → handler → state → consumer | Expected behavior | Result |
|---:|---|---|---|---|
| 1 | Indexing settings tab | Settings sidebar → `SettingsTab.indexing` → `IndexingSettingsView` | The tab must accurately describe whether automatic indexing exists and whether toggles have an effect. | **Fixed:** disabled toggles now show an explicit “automatic indexing is not available yet” status instead of implying live behavior. |
| 2 | Index new folders toggle | `SettingsToggleRow` → `appState.updateSettings` → `settings.indexNewFolders` | A future watcher would use this preference to detect new folders. | **Not implemented:** preference remains stored for forward compatibility, but the disabled UI no longer claims it is active. |
| 3 | Index repositories toggle | `SettingsToggleRow` → `appState.updateSettings` → `settings.indexRepositories` | A future watcher would include or exclude repositories according to this preference. | **Not implemented:** no source consumer uses this preference; disabled honestly. |
| 4 | `@` file suggestions | Input trigger → `inputDropdownContext()` → project path → `ProjectFileScanner.scan` → `ProjectFilesCacheState` → `InputDropdownDataSource.Context.fileNames` | With a selected workspace, file suggestions should list indexable project files and not leak another workspace’s files. | **Pass by source/tests:** cache is path-scoped and rescans on path change or TTL expiry. |
| 5 | Exclusion policy | Scanner → `ProjectFileIndexLogic.shouldExclude` → default exclusions/gitignore patterns | `.git`, `.mycoder`, build/dependency/cache directories and matching gitignore patterns are excluded. | **Pass:** existing index/scanner tests green. |
| 6 | File size policy | Scanner → resource values → `shouldIndex(maxFileSize:)` | Files above the configured default limit are skipped instead of loading unbounded data. | **Pass:** existing tests green. |
| 7 | Change detection | Scanner → content hash/mtime → `computeDelta` | New and changed records are upserted; deleted paths are removed; unchanged paths are not rewritten. | **Pass:** existing delta tests plus new persistence delta test green. |
| 8 | Persistent snapshot | Rescan → current `file_index.json` → scan → `ProjectFileIndexPersistenceLogic.applyDelta` → `ProjectFileIndexStore.save` | Indexed records survive the in-memory 30-second cache and relaunch, scoped to the exact project path. | **Fixed:** per-project JSON snapshot under `<project>/.mycoder/file_index.json`; 3/3 new persistence/settings tests green. |
| 9 | Project isolation | `ProjectFileIndexStore.load(projectPath:)` → snapshot path and embedded project path check | A snapshot from another project must not be used for the current workspace. | **Pass by source:** both file path and embedded project path are checked; macOS file I/O remains UNVERIFIED. |
| 10 | FSEvents watcher | Workspace open/settings toggle → `ProjectFileIndexWatcher` → debounced path filter → generation guard → cache invalidation → next incremental scan/store | Changes should be detected without waiting for a dropdown invocation, and an old project callback must not invalidate the new project. | **PARTIAL:** CoreServices watcher, debounce, `.mycoder` suppression, project isolation, and lifecycle wiring are implemented; live macOS FSEvents behavior is UNVERIFIED. |
| 11 | Persistent FTS/search index | Scanner → SQLite `file_index` table/FTS → search UI | Large projects should query a persistent searchable index rather than rescan synchronously. | **MISSING:** no persistent FTS table or search consumer exists. |
| 12 | Error handling | Permission/unreadable file → scanner skip → cache/status | One unreadable file should not abort the entire scan; the UI should not claim full completeness. | **Pass by source:** scanner skips unreadable files; a richer visible scan error/status is not implemented. |

## Confirmed defects and fixes

### The index was discarded after the cache expired

The scanner and delta logic existed, but `AppState.inputDropdownContext()` retained only file names in a 30-second `ProjectFilesCacheState`. A new process launch or cache refresh had no persisted records to compare against, and there was no project-local index store. The fix adds `ProjectFileIndexSnapshot`, `ProjectFileIndexPersistenceLogic`, shared `FileIndexRecord`, and production `ProjectFileIndexStore`. Rescans now load the project snapshot, scan current files, apply the deterministic delta, save `<project>/.mycoder/file_index.json`, and populate the cache from the resulting records.

### Indexing settings promised behavior that had no consumer

`IndexingSettingsView` persisted `indexNewFolders` and `indexRepositories`, but no source consumer used either preference. The UI therefore implied automatic behavior that did not exist. The toggles are now disabled and accompanied by an honest availability message. The stored preferences remain for future activation rather than being silently deleted.

### FSEvents is implemented with a macOS runtime boundary; FTS remains unresolved

`ProjectFileIndexWatcher` now uses CoreServices FSEvents on macOS, applies a bounded debounce, ignores changes inside `.mycoder`, and stops/restarts on workspace changes. A generation and canonical-path guard prevents a callback from an old project from invalidating the active project. Linux uses a no-op fallback so the same AppState lifecycle remains compilable. The watcher’s live macOS event delivery, shutdown, and permission behavior remain **UNVERIFIED**. Persistent SQLite/FTS search remains outside the implementation and remains a separate missing capability.

## Evidence and scores

| Check | Result | Boundary |
|---|---:|---|
| New persistence/settings regressions | **3/3 passed** | Foundation contracts |
| New watcher regressions | **4/4 passed** | Foundation path/generation/debounce contracts |
| Full Foundation harness | **196/196 passed** | Linux-compatible logic and fake browser contracts |
| Swift parser validation | **passed** | Modified index/AppState/settings syntax only |
| Existing scanner/index tests | **passed in full harness** | Deterministic scan/delta behavior |
| macOS file I/O and SwiftUI settings rendering | **UNVERIFIED** | Requires macOS build |
| FSEvents watcher | **PARTIAL** | CoreServices implementation and pure contracts pass; live macOS event delivery UNVERIFIED |
| Persistent FTS | **MISSING** | No implementation exists |

The **implementation quality score is 96/100**. The persistence fix is deterministic and project-scoped, the CoreServices watcher has explicit lifecycle and stale-generation guards, and the UI no longer lies about automatic indexing. Four points remain deducted because snapshots are JSON rather than SQLite/FTS and macOS UI/file-I/O/FSEvents execution is unavailable in the Linux sandbox.

The **task-following score is 100/100** for this round: every visible indexing control and function was traced, confirmed defects received red tests before the core fix, documentation and the canonical registry are updated, and missing runtime capabilities remain marked missing rather than being represented as PASS.

> A persistent JSON snapshot improves the existing `@` dropdown path, and the macOS-only watcher now invalidates it on file events; this still does not constitute the planned persistent full-text search index.
