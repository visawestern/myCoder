# Activity 27 — FSEvents Dynamic Reindexing

## Audit objective

This round audits **STO-07 FSEvents Dynamic Reindexing** from workspace selection and branch updates through `ProjectFileIndexWatcher`, CoreServices stream creation, callback path filtering, debounce scheduling, generation/project guards, cache invalidation, and watcher teardown/restart.

Round 61 already implemented the CoreServices watcher and pure callback guards. The current adversarial audit found a lifecycle UX/performance defect: every `selectedWorkspace` assignment restarted the watcher and cleared the file-index cache, even when only `Workspace.branch` changed and the project path remained identical. Branch updates are common during repository actions and should not cause a needless FSEvents stream teardown or synchronous file rescan on the next `@` invocation.

## Lifecycle and action checklist

| # | UI/control/action/function | Chain traced | Expected behavior | Result |
|---:|---|---|---|---|
| 1 | Workspace selection | `selectedWorkspace` didSet → watcher lifecycle | Start a watcher for a newly selected project path and clear the old project cache. | **Pass:** path changes request restart; native runtime UNVERIFIED. |
| 2 | Workspace cleared | selected workspace → `nil` → watcher stop | Stop the old watcher and clear cache when no project remains active. | **Pass by lifecycle policy/source.** |
| 3 | Switch project A→B | old/new canonical paths → `shouldRestart` | Stop A, increment generation, start B, and reject stale A callbacks. | **Pass by source/tests.** |
| 4 | Branch-only workspace update | `updateWorkspaceBranch` reassigns same-path `Workspace` | Update branch/session metadata without restarting watcher or clearing project file cache. | **Fixed and tested in Round 73.** |
| 5 | Watcher start | `ProjectFileIndexWatcher.start` → `FSEventStreamCreate` → dispatch queue | Create one stream for the canonical project path; avoid duplicate starts. | **Pass by source; CoreServices runtime UNVERIFIED.** |
| 6 | Watcher stop | `stop` → cancel debounce → stop/invalidate/release stream | Release stream resources and prevent delayed callbacks after teardown. | **Pass by source; native shutdown UNVERIFIED.** |
| 7 | File event inside project | CoreServices callback → `shouldInvalidate` → debounce | Invalidate only for project files and coalesce bursts into one refresh. | **Pass by pure tests/source; live event delivery UNVERIFIED.** |
| 8 | Event outside project | callback path → project-path boundary | Ignore unrelated projects and similarly prefixed paths. | **Pass by existing watcher logic tests.** |
| 9 | `.mycoder` event | callback path → relative component filter | Ignore index snapshots and watcher metadata changes to avoid self-trigger loops. | **Pass by existing watcher logic tests.** |
| 10 | Stale callback after project switch | event project/generation → `shouldApply` → MainActor | Do not clear the newly active project cache for an old watcher event. | **Pass by existing generation tests.** |
| 11 | Debounce interval | `debounceNanoseconds` → `asyncAfter` | Keep bounded debounce and cancel previous pending work on new events. | **Pass by source/tests.** |
| 12 | Cache invalidation | valid callback → `projectFilesCache=nil` | Cause the next file dropdown request to rescan the active project. | **Pass by source; native callback runtime UNVERIFIED.** |
| 13 | FSEvents unavailable platform | `#if canImport(CoreServices)` fallback | Keep Linux/build tooling compilable with safe no-op watcher behavior. | **Pass by harness design.** |
| 14 | Indexing settings | `IndexingSettingsView` → `IndexingSettingsLogic` | Do not imply unavailable automatic indexing; disclose on-demand status honestly. | **Pass by prior audit; native UI UNVERIFIED.** |
| 15 | Persistent FTS | watcher/index → SQLite FTS | Provide persistent large-project full-text search. | **MISSING:** separate IDX-03 capability, not falsely claimed by this watcher. |

## Confirmed defect and TDD evidence

### Branch-only workspace mutations restarted the watcher

`selectedWorkspace.didSet` called `updateProjectFileIndexWatcher(for:)` for every assignment. `updateWorkspaceBranch` copies the current workspace, changes only `branch`, and reassigns it. That sequence stopped the active FSEvents stream, incremented the generation, cleared the project file cache, created a new watcher, and forced a fresh synchronous scan on the next `@` dropdown access despite the project path being unchanged.

`ProjectFileIndexWatcherLifecycleLogicTests` was written first. The red run failed because the path-change policy did not exist. The green `shouldRestart(oldProjectPath:newProjectPath:)` canonicalizes both paths and returns false for path-stable mutations, true for project creation, clearing, or actual path changes. `selectedWorkspace.didSet` now invokes the watcher update only when that policy returns true.

## Remaining limitations

STO-07 remains **PARTIAL**. Source and pure contracts cover path filtering, debounce, generation isolation, path-stable lifecycle behavior, and resource teardown. Live CoreServices event delivery, stream shutdown, permissions, filesystem races, and macOS SwiftUI observation require native verification. Persistent SQLite/FTS remains missing and is tracked separately as IDX-03.

## Evidence and scores

| Check | Result | Boundary |
|---|---:|---|
| Red watcher lifecycle regression | **failed as expected** | Missing path-change restart contract |
| Green watcher lifecycle regressions | **3/3 passed** | Same path no restart; path/nil transitions restart |
| Full Foundation harness | **245/245 passed** | Existing contracts plus STO-07 regressions |
| Swift parser validation | **passed** | Lifecycle helper and MyCoderApp wiring |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| Native CoreServices FSEvents | **UNVERIFIED/PARTIAL** | Requires macOS runtime |
| Persistent SQLite/FTS | **MISSING** | Separate IDX-03 capability |

The **implementation quality score is 95/100**. The watcher no longer churns on branch-only metadata changes and existing debounce/generation guards remain intact; native event/runtime behavior remains.

The **task-following score is 100/100**. Every watcher lifecycle action and callback function was traced, the confirmed path-stable restart defect received a red test before the fix, and native-only behavior remains explicitly UNVERIFIED.

> A watcher is scoped to a project path, not to every metadata mutation of the workspace value; branch changes must not invalidate an unchanged file tree.
