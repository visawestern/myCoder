# Activity 18 — Skills Management Tab

## Audit objective

This round audits **SET-04 Skills Management Tab** from the Settings tab selection through `SkillsSettingsView`, `AgentResourceLibraryView`, `AgentResourceCatalog`, `AgentResourceInstaller`, `SkillRegistryManager`, `AgentResourcesLoader`, and the installed-skill rows. Every visible control was traced to its mutation, refresh callback, and failure behavior.

The existing registry note was stale: the library already had catalog **Update**, dependency-aware install, and dependency hints. The audit confirmed two current defects: updating a disabled skill reset it to enabled, and the library’s destructive **Uninstall** button executed without confirmation even though the installed-row trash action did confirm. Both were fixed with red tests first. Bulk operations and skill export/import remain genuinely absent and keep SET-04 at PARTIAL.

## Button and action checklist

| # | UI control/action | Chain traced | Expected behavior | Result |
|---:|---|---|---|---|
| 1 | Settings → Skills tab | `SettingsView` `.skills` case → `SkillsSettingsView` | Open the Skills screen without losing the Settings container. | **Pass by source; macOS visual runtime UNVERIFIED.** |
| 2 | Search skills field | `$searchQuery` → `AgentResourceLoader.filterSkills` for installed rows and `AgentResourceLibraryLogic.filterSkills` for catalog rows | Trim whitespace; case-insensitive search should match relevant skill metadata. | **Pass:** catalog searches name/description/category/id; installed search matches name/source only. |
| 3 | Library catalog load | `.onAppear` → `loadCatalog` → `AgentResourceCatalog.loadBundled` → nested bundle lookup | Show progress while loading and an actionable error when the catalog is missing/corrupt. | **Pass by source:** loading/error/empty states exist; live bundle packaging remains UNVERIFIED. |
| 4 | Library Install | `Button` → `Task` → `install` → `installSkillWithDependencies` → dependency resolver → MCP installs → skill file + registry → `onInstalled` | Install the selected skill, install declared MCP dependencies first, report unresolved runtimes, refresh the screen. | **Pass/partial:** dependency hints and unresolved notes exist; no transactional rollback if a later dependency or skill write fails. |
| 5 | Installed state badge | catalog/file check → `LibraryItem.isInstalled` → Install/Update/Uninstall branch | Reflect the actual `.mycoder/skills/<id>/SKILL.md` presence. | **Pass:** filesystem check is deterministic; malformed registry metadata can still be silently treated as empty. |
| 6 | Library Update | `Button` → `update` → `updateSkill` → version check → `installSkill` → registry upsert | Replace catalog content while preserving the user’s enabled/disabled preference. | **Fixed:** pre-fix update recreated the record with `isEnabled = true`; Round 64 now preserves existing state. |
| 7 | Library Uninstall | `Button` → `uninstallCandidate` → confirmation alert → `uninstall` → remove directory/config and registry | Require explicit confirmation before destructive removal and refresh only after success. | **Fixed:** library uninstall now uses item-specific confirmation; native alert interaction UNVERIFIED. |
| 8 | Installed enable/disable | `InstalledSkillRow` button → `SkillRegistryManager.setEnabled` → `reloadSkills` | Toggle only the selected skill and reflect the persisted state. | **Partial:** persistence exists, but the view ignores thrown errors and refreshes even when the mutation fails. |
| 9 | Installed-row trash | trash button → alert → `remove` → filesystem removal + registry removal → reload | Warn, delete the exact skill folder, remove registry metadata, and refresh. | **Partial:** alert and path are present; `try?` suppresses filesystem/registry errors and can leave source and registry inconsistent. |
| 10 | Dependency hint | catalog item → `AgentDependencyResolver.resolve` → `dependencyHint` | Show declared runtime/MCP requirements and whether they are satisfied. | **Pass/partial:** hints are visible; there is no dedicated dependency-resolution dialog or interactive remediation. |
| 11 | Installed count and empty state | filtered installed list → count/`settingsEmptyState` | Count installed skills and explain how to install when empty. | **Pass by source:** count is based on filesystem-loaded entries; native layout UNVERIFIED. |
| 12 | Installed skill display | `AgentResourcesLoader.loadSkills` → `.mycoder/skills` folders → `SKILL.md` → rows | Display installed skill name, source, version, disabled badge, and path. | **Partial:** version/enabled state comes from registry, but display name/source are filesystem-derived and source is hardcoded `myCoder`. |
| 13 | Catalog update badge | registry version vs catalog version → `updateAvailable` | Show Update only when versions differ and catalog version is non-empty. | **Pass:** version mismatch contract exists and update is idempotent when no update is available. |
| 14 | Catalog/library search result refresh | `installedRevision` increment → `visibleItems` recomputation | Reflect install/update/uninstall state immediately after a successful action. | **Pass by source:** callback and revision refresh are wired. |
| 15 | Catalog dependency failure | installer throws → `installErrors[item.id]` → error text | Keep the item visible and explain a failed install without claiming success. | **Pass/partial:** thrown errors are shown; asynchronous macOS filesystem and catalog-resource failures are UNVERIFIED. |
| 16 | Skills tab tool availability banner | `appState.supportsToolcallForSelection` → warning text | Explain when the selected model/provider cannot use skills/tools. | **Pass by source:** warning is conditional; the capability value’s native provider runtime is UNVERIFIED. |
| 17 | Bulk operations | expected SET-04 control → no production control or service | Provide select-all/bulk enable, disable, update, remove, or import/export if the story claims them. | **MISSING by feature scope:** no bulk action model, no export/import contract, and no selection controls exist. |

## Confirmed defects and TDD evidence

### Update reset a disabled skill

`AgentResourceInstaller.updateSkill` called `installSkill`, and `installSkill` always upserted a new registry record with `isEnabled: true`. Therefore, a user who intentionally disabled a skill could update it and silently re-enable it. The red test `SkillUpdateStateTests.updatePreservesDisabledState` failed with `true == false` before the fix. The green implementation reads the existing registry record and preserves its enabled state; new installs still default to enabled. The enabled-state regression also passes.

### Library uninstall had no confirmation

The installed row used an alert, but `AgentResourceLibraryView`’s catalog Uninstall button immediately launched the destructive task. `SkillUninstallPolicyTests` was written red first and failed because the policy did not exist. The green policy supplies item-specific title/message copy, and the library now stores the candidate and presents a cancel/destructive-confirmation alert before invoking `uninstall`.

## Remaining limitations

SET-04 remains **PARTIAL**. The library has install/update/uninstall and dependency hints, but it does not provide bulk enable/disable/update/remove, skill export/import, or an interactive dependency-resolution dialog. Install operations are not transactional across dependencies: a dependency may remain installed if a later skill write fails. The installed-row enable/disable and direct trash handlers still suppress errors with `try?`; this is a further UX/error-surface candidate for a later round. Linux cannot validate SwiftUI alerts, AppKit Settings presentation, bundled-resource packaging, or native filesystem behavior.

## Evidence and scores

| Check | Result | Boundary |
|---|---:|---|
| Red update-state regression | **1 expected failure** | Disabled state reset before implementation |
| Green update-state regressions | **2/2 passed** | Disabled and enabled state preservation |
| Red uninstall-policy regression | **failed as expected** | Missing confirmation policy before implementation |
| Green uninstall-policy regression | **1/1 passed** | Item-specific destructive confirmation copy |
| Swift parser validation | **passed** | Installer, policy, and library source parsed successfully |
| Full Foundation harness | **206/206 passed** | Linux-compatible contracts including SET-04 regressions |
| Native SwiftUI/AppKit interaction | **UNVERIFIED** | Requires macOS runtime |

The **implementation quality score is 94/100**. Update-state preservation and destructive confirmation are now explicit and tested. Four points remain deducted for suppressed mutation errors, non-transactional dependency installation, and absent bulk/export/import capabilities.

The **task-following score is 100/100**. Every visible Skills action was traced through source, both confirmed defects received red tests before fixes, the registry was corrected, and absent features remain marked rather than implied.

> A management UI must preserve user preferences across content updates and must never make a destructive action one click away when a comparable destructive action already requires confirmation.
