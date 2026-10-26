# Activity 49 — Storage Transfer and Deletion UX

## Audit objective

This round audits **STO-27**, **STO-28**, and **STO-29** from Storage Settings actions through bundle validation, registry/settings replacement, project backup prerequisites, chunked deletion, progress/cancellation, registry mutation, and the explicit retirement of the CLI-import toggle.

## Full chain checklist

| Story | Chain audited | Expected behavior | Result |
|---|---|---|---|
| STO-27 | Export/Import buttons → panels → versioned bundle → decode/validation → canonical registry/settings replacement → refresh/notices | Export is atomic and visible; import requires confirmation, rejects malformed/version-mismatched data, normalizes duplicate registry entries, replaces state only after full decode, refreshes UI, and reports failure/success. | **Fixed Round 95 imported-registry normalization; 332/332 Foundation tests; native panels/filesystem/UserDefaults runtime UNVERIFIED.** |
| STO-28 | Delete icon → typed project-name confirmation → backup/preservation gate → background chunked executor → progress/cancel → completion-only registry removal → active-workspace cleanup | Large deletion must not block the UI; progress and cancellation must be visible; backup is mandatory when a DB exists; cancelled/failed deletion retains the registry entry; only completed deletion removes it. | **Fixed Round 95 UI wiring: executor now runs off the main actor with cooperative cancel/progress and completion-only registry mutation; native filesystem/SwiftUI runtime UNVERIFIED.** |
| STO-29 | Registry/settings/DB/reset/UI inventory → retired CLI-import concept | Removed feature must not remain as an active toggle, migration path, database field, or action. | **FUTURE/removed by explicit clean-slate HTTP-only directive; no implementation added.** |

## Detailed manual trace

| # | Action/function | Chain and invariant | Result |
|---:|---|---|---|
| 1 | Export app configuration | `StorageSettingsView.exportAppConfiguration` opens `NSSavePanel`, calls `AppConfigurationBackupStore.export`, and presents a success/failure notice. | **Pass by source; native panel/filesystem UNVERIFIED.** |
| 2 | Import app configuration | `NSOpenPanel` restricts to JSON, stores the URL, and presents a destructive confirmation before any write. | **Pass by source/tests.** |
| 3 | Import decode boundary | Bundle schema/date decoding, registry decoding, and settings decoding all complete before writes begin; unsupported schema returns false. | **Pass by source/tests.** |
| 4 | Imported registry normalization | Decoded registry is passed through `ProjectRegistryLogic.deduplicated` before atomic save, preventing duplicate canonical paths from being installed. | **Fixed Round 95 red/green.** |
| 5 | Import state refresh | On success, AppState reloads settings and project registry and Storage Settings refreshes statistics; failure preserves current visible state and notice. | **Pass by source.** |
| 6 | Project deletion confirmation | Trash action is disabled during an active deletion; typed project name is required by `ProjectDeleteConfirmation` before the destructive button enables. | **Pass by source/tests.** |
| 7 | Backup safety | For projects with a database, backup creation and preservation both gate deletion; failure produces a visible failure notice and leaves registry state. | **Pass by source/tests.** |
| 8 | Background deletion | Storage Settings starts a utility task; the UI no longer executes the chunked removal synchronously on the main actor. | **Fixed Round 95.** |
| 9 | Progress display | `ProjectDeletionExecutor.onProgress` updates a thread-safe snapshot; the main actor polls it into `ProgressView(value: deletionProgress)` and an item-count label. | **Fixed Round 95 by source acceptance test; native rendering UNVERIFIED.** |
| 10 | Cancellation | Visible `Cancel deletion` calls a thread-safe token; executor checks it before chunks/items and returns `.cancelled`. Leaving the view also requests cancellation and waits for the worker outcome. | **Fixed Round 95 by source/parser; native timing UNVERIFIED.** |
| 11 | Completion-only registry removal | `.completed` is the only outcome allowed to remove the registry entry; cancellation/failure notices retain the entry. | **Pass by existing tests/source.** |
| 12 | Active workspace cleanup | After successful registry save, a deleted active workspace clears navigation history and selection; failed registry save reports that data was deleted but registry state could not be saved. | **Pass by source; native state transition UNVERIFIED.** |
| 13 | Retired CLI-import concept | No active toggle, CLI-history state, migration code, reset scope, or settings action remains; STO-29 remains FUTURE/removed. | **Pass by inventory and policy.** |

## Confirmed defects and TDD evidence

### STO-27 — imported duplicate registry paths were saved raw

`AppConfigurationBackupStore.import` decoded the registry and wrote it directly. A valid bundle could therefore reintroduce duplicate canonical project entries even though normal registry operations deduplicate paths. A red source regression was written first. Import now canonicalizes the decoded registry with `ProjectRegistryLogic.deduplicated` before atomic save; settings refresh and visible notices remain unchanged.

### STO-28 — deletion progress/cancellation hooks were orphaned from the UI

`ProjectDeletionExecutor` already supported bounded chunks, `shouldCancel`, and `onProgress`, but `StorageSettingsView.deleteProject` called it synchronously without either hook. That could freeze the Settings UI and gave the user no progress or cancellation control. A red source-wiring regression was written first. Storage Settings now runs the backup and deletion workflow in a utility task, exposes progress and `Cancel deletion`, propagates a thread-safe cancellation token, polls progress on the main actor, and removes the registry only after `.completed`.

### STO-29 — intentional removal, not an implementation defect

The CLI-import toggle was explicitly removed by the product directive. The audit found no active source chain to repair and preserved FUTURE status rather than recreating a retired feature.

## Evidence

| Check | Result | Boundary |
|---|---:|---|
| STO-27 import-normalization red test | **failed as expected → 1/1 passed** | Persistent Python source acceptance |
| STO-28 deletion-wiring red test | **failed as expected → 1/1 passed** | Persistent Python source acceptance |
| STO-28 outcome/backup tests | **existing tests pass** | Foundation safety logic |
| Full Foundation harness | **332/332 passed** | Linux-safe suites |
| Adversarial source checks | **12/12 passed** | Existing web/model safety invariants |
| Swift parser validation | **passed** | Changed backup/deletion/Settings Swift |
| `git diff --check` | **passed** | No trailing whitespace |

## Status and scores

The confirmed STO-27 and STO-28 source-level defects are fixed. STO-27 remains **PARTIAL** for native panels/filesystem/UserDefaults and cross-machine path relinking. STO-28 remains **PARTIAL** for native filesystem behavior, SwiftUI progress rendering, cancellation timing, and macOS permission failures. STO-29 remains **FUTURE** by explicit product policy. No Linux result is represented as native runtime proof.

| Story | Code quality | Task adherence | Target-runtime confidence |
|---|---:|---:|---:|
| STO-27 | 99/100 | 100/100 | 0/100 |
| STO-28 | 98/100 | 100/100 | 0/100 |
| STO-29 | 100/100 | 100/100 | 0/100 |

> The deletion action now exposes the safety state users need: it is working, how far it has progressed, and how to stop it. The registry remains until the filesystem outcome is definitively completed.
