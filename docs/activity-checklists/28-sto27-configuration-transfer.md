# Activity 28 — Registry and Settings Export/Import

## Audit objective

This round audits **STO-27 Registry+Settings Export/Import** from the two visible Storage settings buttons through `NSSavePanel`/`NSOpenPanel`, `AppConfigurationBackupStore`, `AppConfigurationBackupLogic`, `ProjectRegistryLogic`, `AppSettings`, `UserDefaults`, visible reloads, and the post-import UI state. The existing project `.zip` backup actions are traced separately so a project history archive is not confused with a global configuration bundle.

The adversarial questions were: does the bundle contain both advertised payloads; does it reject malformed or unsupported data; can an import silently replace local state; do export/import failures reach the user; does a successful import refresh visible settings and registry state; and what remains unverified on macOS?

## Full chain checklist

| # | UI/control/action/function | Chain traced | Expected behavior | Result |
|---:|---|---|---|---|
| 1 | Export app configuration button | `projectsAdminSection` → `exportAppConfiguration` | Open a save panel with a clear JSON filename and export global registry + app settings. | **Pass by source; native panel UNVERIFIED.** |
| 2 | Save-panel cancellation | `NSSavePanel.runModal` → guard | Cancel must make no file write and show no false success. | **Pass by source; native panel UNVERIFIED.** |
| 3 | Export payload capture | `AppConfigurationBackupStore.export` → `ProjectRegistryLogic.load` + `AppSettings.load` | Capture the current registry and Codable `AppSettings` independently. | **Pass by source/tests.** |
| 4 | Export bundle schema | `AppConfigurationBackupLogic.encode` → version/date/payload fields | Produce deterministic, ISO-8601, sorted-key JSON with an explicit schema version. | **Pass by existing round-trip test.** |
| 5 | Export destination write | encoded bundle → `Data.write(options: .atomic)` | Avoid partially written destination files. | **Pass by source; filesystem runtime UNVERIFIED.** |
| 6 | Export failure | store Bool → StorageSettingsView state | Surface a visible failure instead of discarding the Bool. | **Fixed Round 74:** typed failure notice and alert. |
| 7 | Import app configuration button | `projectsAdminSection` → `importAppConfiguration` | Open a single-file JSON open panel with an import action. | **Pass by source; native panel UNVERIFIED.** |
| 8 | Open-panel cancellation | `NSOpenPanel.runModal` → guard | Cancel must not mutate registry, defaults, or visible state. | **Pass by source; native panel UNVERIFIED.** |
| 9 | Import overwrite boundary | selected URL → pending URL → confirmation alert → `performAppConfigurationImport` | Warn that registry/settings will be replaced and require explicit confirmation before any write. | **Fixed Round 74; pure confirmation contract tested.** |
| 10 | Malformed bundle | file data → `AppConfigurationBackupLogic.decode` | Reject malformed JSON, missing fields, invalid date, and unsupported schema without mutation. | **Pass by existing decode guards; native file selection UNVERIFIED.** |
| 11 | Registry decode | bundle registry payload → `ProjectRegistryDocument` | Reject invalid registry payload before either persistence step. | **Pass by source.** |
| 12 | Settings decode | bundle settings payload → `AppSettings` | Reject invalid settings payload before persistence. | **Pass by source.** |
| 13 | Registry persistence | decoded registry → `ProjectRegistryLogic.save` atomic write | Save registry only after both payloads validate; report failure. | **Pass by source; filesystem runtime UNVERIFIED.** |
| 14 | Settings persistence | decoded settings → `settings.save(to:)` | Write settings to the active defaults domain. | **Pass by source; AppState’s separate runtime defaults reload is macOS/UI-bound.** |
| 15 | Import failure | store Bool → failure notice | Invalid data or persistence failure must be visible and must not trigger a false refresh. | **Fixed Round 74; typed failure notice and alert.** |
| 16 | Import success | store success → reload `AppSettings` + `refreshProjectRegistry` + `refreshStats` | Refresh settings, registry list, and storage statistics after successful replacement. | **Pass by source; native SwiftUI rendering UNVERIFIED.** |
| 17 | Project registry portability | imported `ProjectRegistryEntry.path` values → orphan/relink UI | Preserve registry records, then make missing paths visible for relinking rather than silently deleting them. | **Pass by source:** orphan rows and relink action remain available. Cross-machine path remapping is not automatic. |
| 18 | Credentials/provider catalogs | global bundle fields → AppSettings only | Do not claim that Keychain secrets, custom provider catalog, or web browser cookies are inside this bundle unless explicitly encoded. | **Honest boundary:** STO-27 bundle is registry + AppSettings; separate stores remain outside scope. |
| 19 | Existing project backup export | project row → `exportProjectBackup` → `ProjectBackupLogic.export` | Keep project `.mycoder` history export separate from global configuration export. | **Pass by source; macOS `ditto` UNVERIFIED.** |
| 20 | Existing project backup import | project row → `importProjectBackup` → `ProjectBackupLogic.importBackup` | Restore only the selected project data and refresh stats after success. | **Pass by source; native runtime UNVERIFIED.** |

## Confirmed defects and TDD evidence

### Import silently replaced local configuration without confirmation

`importAppConfiguration` previously moved directly from `NSOpenPanel` success to `AppConfigurationBackupStore.import`. That store writes the decoded project registry and settings, replacing local state. Unlike project deletion and storage reset, no confirmation was shown. A user could select the wrong valid bundle and lose the current registry/settings without a second chance.

### Export and import failures were silently discarded

`exportAppConfiguration` ignored the store’s Bool return. `importAppConfiguration` used `guard ... else { return }`, so malformed input, unsupported schema, a failed write, or an unreadable file produced no visible explanation. This made a failed migration indistinguishable from a cancelled panel.

`AppConfigurationTransferLogicTests` was written first. The red run failed because the tested transfer contract did not exist. The green fix introduces a typed operation/outcome notice and a mandatory import-confirmation contract. The view now holds the selected import URL until the user explicitly chooses “Import and replace”; export/import results are converted to visible success/failure alerts, and only successful imports refresh app state.

## Evidence and scores

| Check | Result | Boundary |
|---|---:|---|
| Red transfer UX regressions | **failed as expected** | Transfer safety/notice contract absent before implementation |
| Green transfer UX regressions | **3/3 passed** | Confirmation required; export/import failures produce visible notices |
| Full Foundation harness | **248/248 passed** | Existing contracts plus STO-27 transfer regressions |
| Swift parser validation | **passed** | Transfer logic and StorageSettingsView |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| AppKit save/open panels | **UNVERIFIED** | Requires macOS runtime and actual user interaction |
| macOS filesystem permissions/atomic replacement | **UNVERIFIED** | Requires native filesystem execution |
| Cross-machine path remapping | **PARTIAL** | Imported paths are preserved; orphan/relink is manual |
| Keychain/custom-provider/web-cookie migration | **OUT OF SCOPE** | Not encoded by registry + AppSettings bundle |

`STO-27` remains **PARTIAL**. The global bundle is versioned and validated; destructive replacement is confirmed; failures are visible; and successful import refreshes the settings page state. Native panels, filesystem permissions, actual cross-machine path relinking, and external secret/session stores require macOS or a separately designed migration contract.

The **implementation quality score is 96/100**. The confirmed silent-failure and unconfirmed-overwrite defects are fixed with a small tested state contract, while native panel behavior and portability boundaries remain.

The **task-following score is 100/100**. Every visible control and persistence function was traced, red tests preceded the fixes, the canonical registry/checklist/report are updated, and unsupported macOS/runtime behavior is explicitly UNVERIFIED.

> A configuration import is a destructive replacement of two global stores; selecting a file is not the same as consenting to replace the current configuration.
