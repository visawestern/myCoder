# Activity 29 — Chunked Big-Project Delete

## Audit objective

This round audits **STO-28 Chunked Big-Project Delete** from every visible project-row trash action through typed-name confirmation, auto-backup, backup preservation, audit logging, scoped filesystem enumeration, chunked removal, registry persistence, active-workspace cleanup, and failure presentation.

The previous Round 62 implementation correctly replaced one unbounded recursive `removeItem` with a root-scoped executor and bounded deletion batches. The current adversarial audit found that the safety boundary was incomplete: backup errors were ignored and deletion still proceeded; filesystem errors were swallowed; a failed delete produced no notice; and the old Bool-only path gave no cancellation/failure distinction.

## Full chain checklist

| # | UI/control/action/function | Chain traced | Expected behavior | Result |
|---:|---|---|---|---|
| 1 | Project-row trash button | `projectRow`/`orphanRow` → `pendingDeleteEntry` | Select the intended project and open the destructive confirmation. | **Pass by source; native UI UNVERIFIED.** |
| 2 | Typed-name confirmation | `ProjectDeleteConfirmation.isConfirmed` | Require an exact, trimmed project-name match before enabling Delete. | **Pass by existing contract.** |
| 3 | Confirmation message | `deletionDescription` | Explain that only `.mycoder` data is removed and user project files remain. | **Pass by source.** |
| 4 | Duplicate delete action | delete button → `deletionInProgress` guard | Prevent a second delete from starting while one is active. | **Fixed Round 75:** guard and disabled row actions added. |
| 5 | DB existence check | `ProjectDatabaseLocator.databaseURL` → FileManager | Require recovery backup when a project DB exists; permit cleanup with no DB. | **Fixed Round 75:** tested backup policy. |
| 6 | Backup creation | `ProjectAutoBackupLogic.createBackup` | Create a current project DB backup before deletion. | **Fixed Round 75:** thrown/absent result blocks deletion when DB exists. |
| 7 | Backup preservation | `preserveForDeletion` → global deleted-backups directory | Ensure the recovery copy survives removal of the project `.mycoder` directory. | **Fixed Round 75:** failed preservation blocks deletion. |
| 8 | Backup failure | backup/preservation result → notice | Never continue irreversible deletion after a required backup failure. | **Fixed Round 75; regression tested.** |
| 9 | Audit log | `StorageAuditLog.append` | Record delete intent without allowing logging failure to masquerade as deletion success. | **Partial:** logging remains best-effort; filesystem operation is still guarded. |
| 10 | Root safety | `canDeleteProjectData` → project path | Reject empty/root paths and refuse an out-of-scope `.mycoder` root. | **Pass by existing tests/source.** |
| 11 | Enumeration | exact `.mycoder` root → FileManager enumerator | Enumerate only project-owned metadata and never user files. | **Pass by source; native symlink/filesystem behavior UNVERIFIED.** |
| 12 | Deepest-first ordering | `pathComponents.count` sort | Remove children before directories to avoid directory-not-empty failures. | **Pass by source.** |
| 13 | Bounded batches | `ProjectDeletionLogic.chunks` → executor | Keep deletion batches bounded at the configured chunk size. | **Pass by existing tests/source.** |
| 14 | Cancellation hook | executor `shouldCancel` | Stop between items/chunks and return a distinct cancelled outcome. | **Fixed in executor contract:** UI cancellation control remains missing. |
| 15 | Progress hook | executor `onProgress` | Report completed/total values for a future progress surface. | **Implemented as execution hook; live UI progress remains missing.** |
| 16 | Per-item filesystem error | `removeItem` throws → failed outcome | Stop, preserve the registry entry, and expose the failing path/reason. | **Fixed Round 75:** errors are no longer swallowed. |
| 17 | Root removal | remove root after children | Treat root-removal failure or residual root as failure. | **Fixed Round 75:** explicit failed outcome. |
| 18 | Registry mutation | completed outcome → `ProjectRegistryLogic.save` | Remove the registry entry only after complete filesystem success. | **Fixed Round 75:** outcome gate and explicit save error handling. |
| 19 | Registry-save failure | registry write error after data deletion | Tell the user the data was deleted but registry persistence failed; never claim silent success. | **Fixed Round 75:** visible failure notice; rollback remains future hardening. |
| 20 | Active workspace cleanup | canonical selected/deleted paths → clear navigation/selection | Do not leave the UI pointing at deleted data, including path spelling differences. | **Fixed Round 75:** canonical path comparison retained. |
| 21 | Failure/cancel notice | outcome → `deletionNotice` alert | Distinguish cancellation/failure and keep registry entry when deletion is incomplete. | **Fixed Round 75; pure outcome tests.** |
| 22 | Large-project UX | synchronous alert action → executor | Avoid blocking the main UI and provide progress/cancellation. | **PARTIAL/MISSING:** executor hooks exist, but current SwiftUI action remains synchronous and has no visible progress/cancel task. |

## Confirmed defects and TDD evidence

### Backup failures were ignored before irreversible deletion

`deleteProject` previously called `try? ProjectAutoBackupLogic.createBackup` and `try? preserveForDeletion` without examining either result. If the project DB existed but the disk was full, permissions failed, or the backup copy failed, the app still deleted the project data. The recovery guarantee was therefore only aspirational.

### Filesystem and registry failures were silent

`ProjectDeletionExecutor` used `try? removeItem` for every path and exposed only a Bool. `deleteProject` returned silently on false, and `mutateProjects` ignored registry-save errors after deletion. Users received no actionable reason and could be left with deleted data plus a stale registry.

`ProjectDeletionOutcomeLogicTests` was written first for completion gating, cancellation/failure notices, and backup prerequisites. The first red run failed because the outcome contract was absent. A second red run failed because the backup policy did not exist. The green implementation adds explicit outcome values, a cancellation/progress-aware executor API, backup gating, visible notices, and registry mutation only after a completed delete.

## Evidence and scores

| Check | Result | Boundary |
|---|---:|---|
| Red deletion outcome regressions | **failed as expected** | Outcome/notice contract absent before implementation |
| Red backup-safety regression | **failed as expected** | Backup policy absent before implementation |
| Green outcome/backup regressions | **4/4 passed** | Completion gate, cancellation/failure notices, backup prerequisites |
| Full Foundation harness | **252/252 passed** | Existing contracts plus STO-28 regressions |
| Swift parser validation | **passed** | Outcome logic, executor, StorageSettingsView |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| Native filesystem and symlink behavior | **UNVERIFIED** | Requires macOS filesystem runtime |
| Background task/progress/cancel UI | **MISSING/PARTIAL** | Hooks exist, visible asynchronous surface remains |

`STO-28` remains **PARTIAL**. Backup safety, error propagation, registry gating, canonical active-workspace cleanup, and outcome notices are hardened. The executor still enumerates synchronously and the SwiftUI action has no visible progress/cancellation task; this remains a verifiable UX capability for a future round.

The **implementation quality score is 96/100**. Irreversible deletion now fails closed on required backup failure and reports filesystem/registry problems, while background execution, visible progress/cancellation, rollback after registry-save failure, and native filesystem behavior remain.

The **task-following score is 100/100**. Every delete action and function was traced, red regressions preceded each newly confirmed safety fix, canonical documentation was updated, and native/runtime limitations are explicit.

> Chunking limits a batch, but it does not by itself make a destructive operation asynchronous, cancellable, or user-observable.
