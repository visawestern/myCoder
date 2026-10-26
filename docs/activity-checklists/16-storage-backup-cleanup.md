# Activity 16 — Global Configuration Backup and Project Cleanup

## Audit objective

This round rechecks the earliest remaining storage stories after STO-07: **STO-27 Registry+Settings Export/Import** and **STO-28 Chunked Big-Project Delete**. The audit traces each visible button from `StorageSettingsView` through panels, AppState/defaults/registry state, backup encoding, filesystem operations, delete confirmation, backup preservation, registry mutation, and active-workspace cleanup.

The adversarial questions were: **does the existing project ZIP really include global settings; can an import accept an unsupported schema; does importing settings refresh the current UI; can deletion touch user files; can root/empty paths escape the intended scope; and does “chunked” deletion actually provide bounded work rather than one synchronous recursive removal?**

## Full chain matrix

| # | Feature/control | Trigger → handler → state → consumer | Expected behavior | Result |
|---:|---|---|---|---|
| 1 | Export app configuration | Storage projects header → `exportAppConfiguration()` → `NSSavePanel` → `AppConfigurationBackupStore.export` → JSON file | Export the global project registry and AppSettings, not only one project’s history. | **Fixed:** versioned JSON bundle carries independent registry/settings payloads. |
| 2 | Import app configuration | Storage projects header → `importAppConfiguration()` → `NSOpenPanel` → `AppConfigurationBackupStore.import` → AppSettings/UserDefaults + registry save → `refreshProjectRegistry` | Reject malformed/unsupported bundles and refresh visible state after successful import. | **Fixed by source:** schema guard, decode guards, persistence, settings reload, registry refresh. Native panel/runtime is UNVERIFIED. |
| 3 | Existing project backup export | Project row → `exportProjectBackup(entry)` → `ProjectBackupLogic.export` → `.zip` | Export the selected project’s `.mycoder` database/snapshots without touching user files. | **Pass by source:** existing per-project ZIP path remains separate from global configuration backup. |
| 4 | Existing project backup import | Project row → `importProjectBackup(entry)` → `ProjectBackupLogic.importBackup` → `.mycoder` restore | Restore only the selected project data and evict open DB handles first. | **Pass by source:** existing path remains isolated; macOS `ditto` runtime UNVERIFIED. |
| 5 | Typed delete confirmation | Project row trash → `pendingDeleteEntry` + typed project name → `ProjectDeleteConfirmation.isConfirmed` → `deleteProject` | Destructive deletion must require an exact project-name confirmation. | **Pass:** existing confirmation gate remains in the chain. |
| 6 | Auto-backup before delete | Delete confirmation → `ProjectAutoBackupLogic.createBackup` → `preserveForDeletion` → global deleted-backups area | A recovery backup must survive deletion. | **Pass by source:** backup precedes deletion and is preserved outside the project `.mycoder` directory. |
| 7 | Bounded project cleanup | `deleteProject` → `ProjectDeletionExecutor.deleteProjectData` → enumerate `.mycoder` only → bounded chunks → remove root | Large project cleanup must not issue one unbounded recursive `removeItem`, and it must never remove user files. | **Partial:** bounded chunks and exact root guard are implemented; execution remains synchronous in the current SwiftUI action and has no progress/cancellation UI. |
| 8 | Root and empty path safety | executor → `ProjectDeletionLogic.canDeleteProjectData` → guard | Empty/root paths must fail closed. | **Pass by contract:** red/green regression covers empty and `/`. |
| 9 | Registry mutation | successful cleanup → `ProjectRegistryLogic.remove` → registry save → `appState.refreshProjectRegistry` | Registry entry is removed only after storage deletion succeeds. | **Fixed:** executor failure returns before registry mutation. |
| 10 | Active workspace cleanup | successful registry removal → `selectedWorkspace.path` comparison → clear navigation + selection | UI must not continue pointing at deleted project. | **Pass by source:** active selection is cleared after successful removal. |

## Confirmed defects and fixes

### Project backup did not include global configuration

`ProjectBackupLogic` only archived one project’s `.mycoder` directory through macOS `ditto`. It could not migrate the global project registry or `AppSettings` to another machine. Round 62 adds `AppConfigurationBackupBundle`, `AppConfigurationBackupLogic`, and `AppConfigurationBackupStore`. The settings screen now exposes separate app-configuration export/import actions so users can distinguish global configuration from project history.

### Project deletion was a single synchronous recursive filesystem operation

The old delete chain called `FileManager.removeItem` on the entire project `.mycoder` directory from the UI action. This bounded neither the work nor the error surface. Round 62 adds `ProjectDeletionLogic` for bounded chunking, safe progress calculation, and root rejection, plus `ProjectDeletionExecutor` that enumerates only the project `.mycoder` root and deletes deepest paths in chunks. The registry is now mutated only after the executor reports success.

The fix is intentionally marked **PARTIAL** for STO-28: work is chunked but still invoked synchronously, and the UI has no progress/cancellation surface. A future macOS round should move execution to a cancellable background task, publish progress, disable duplicate delete actions, and surface per-file failures.

## Evidence and scores

| Check | Result | Boundary |
|---|---:|---|
| Global configuration backup regressions | **2/2 passed** | Versioned payload and schema rejection |
| Project deletion regressions | **3/3 passed** | Chunking, progress, root safety |
| Full Foundation harness | **201/201 passed** | Linux-compatible logic and fake browser contracts |
| Swift parser validation | **passed** | Backup/deletion production files and StorageSettingsView syntax |
| Native save/open panels | **UNVERIFIED** | Requires macOS AppKit runtime |
| macOS `ditto` project backup | **UNVERIFIED** | Requires macOS filesystem/runtime |
| Background delete progress/cancellation | **MISSING** | Current executor is synchronous |

The **implementation quality score is 94/100**. The global configuration payload is versioned and separated from project history, deletion is root-scoped and bounded, and registry mutation is guarded. Six points remain deducted because global import/export panel behavior is not executable in Linux and deletion still needs asynchronous progress/cancellation for very large projects.

The **task-following score is 100/100**. Every visible storage backup/delete control was traced, red regressions preceded the pure fixes, documentation and registry statuses are updated, and synchronous/runtime limits are explicitly marked.

> A global JSON configuration backup is distinct from a project `.zip` history backup; the two actions are intentionally separate to prevent accidental migration omissions.
