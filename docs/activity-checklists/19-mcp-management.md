# Activity 19 — MCP Server Management

## Audit objective

This round audits **SET-05 MCP Server Management** from the Settings tab into `MCPServersSettingsView`, `AgentResourceLibraryView(mode: .mcpServers)`, `AgentResourcesLoader`, `MCPConfigMutationLogic`, `MCPRegistryManager`, `MCPHealthCheckLogic`, `MCPHealthChecker`, and the installed MCP row. Every visible button and action was manually traced through configuration persistence, registry state, health state, refresh behavior, and failure handling.

The existing registry note was stale: the MCP library already exposes install, update, and uninstall based on catalog version/state. The confirmed defect was lower-level: installed-row enable/disable and remove used silent `try?` configuration mutations, refreshed as if successful, and could leave config and registry out of sync. Round 65 adds a tested mutation contract and an inline error surface.

## Button and action checklist

| # | UI control/action | Chain traced | Expected behavior | Result |
|---:|---|---|---|---|
| 1 | Settings → MCP Servers tab | `SettingsView` `.mcpServers` case → `MCPServersSettingsView` | Open MCP management without losing the Settings container. | **Pass by source; macOS visual runtime UNVERIFIED.** |
| 2 | Search MCP servers field | `$searchQuery` → `AgentResourcesLoader.filterEntries` by server name | Trim and case-insensitively filter configured rows and library cards. | **Pass:** both configured list and library use search paths; native layout UNVERIFIED. |
| 3 | Library catalog load | `AgentResourceLibraryView.onAppear` → `AgentResourceCatalog.loadBundled` | Show loading, no-match, or catalog error state honestly. | **Pass by source:** progress/error/empty states exist; packaged bundle lookup is UNVERIFIED. |
| 4 | Library Install | catalog card → `install` → `installMCPServer` → config merge → registry upsert → refresh | Install URL/stdio config, substitute `{HOME}`, merge env/headers, record metadata, refresh. | **Pass/partial:** source path and registry write exist; remote token/network and native filesystem are UNVERIFIED. |
| 5 | Library Update | catalog version mismatch → `update` → `updateMCPServer` → rewrite config/registry | Rewrite current catalog configuration only when an update is available. | **Pass by source:** update control exists; no separate editable configuration sheet. |
| 6 | Library Uninstall | catalog card → confirmation policy only for skill library currently; MCP `uninstall` task | Remove only selected server and preserve siblings. | **Partial:** installer preserves siblings, but the MCP library uninstall branch still invokes directly without the new explicit confirmation policy. |
| 7 | Configured server health dot | row `.task(id:)` → session cache → recent registry result → `MCPHealthChecker.check` → real HTTP/stdio probe | Green means healthy, red means failing, gray means disabled/unknown; never simply enabled. | **Pass/partial:** real health chain and max-three session limiter exist; live network/stdio probes are UNVERIFIED. |
| 8 | Enable/Disable button | row button → `setDisabled` → config mutation → registry `setEnabled` → `onChanged` | Persist disabled flag and registry state only if both mutations succeed; show error otherwise. | **Fixed:** Round 65 no longer ignores config/registry failures; sibling entries are preserved and errors render inline. |
| 9 | Remove trash button | button → confirmation alert → `remove` → config mutation → registry removal → refresh | Confirm, remove exact server, preserve all other servers, report failures. | **Fixed/partial:** tested config mutation preserves siblings and fails on missing target; native alert/filesystem behavior UNVERIFIED. |
| 10 | Remove confirmation cancel | alert cancel → no mutation | Cancel must leave config and registry untouched. | **Pass by source; native alert interaction UNVERIFIED.** |
| 11 | Configured count and empty state | filtered list → count/`settingsEmptyState` | Count configured entries and direct user to install from the library when empty. | **Pass by source; native layout UNVERIFIED.** |
| 12 | Tool availability warning | `supportsToolcallForSelection` → warning text | Explain when the selected route/model cannot use MCP tools. | **Pass by source; live provider capability runtime UNVERIFIED.** |
| 13 | MCP config parsing | `.mycoder/mcp.json` → `loadMCPServers` → URL/command/args/disabled | Load URL and stdio transports without dropping args or disabled state. | **Pass:** parser preserves URL, command, args, and disabled flag. |
| 14 | Health cache behavior | `MCPHealthSession` cache + `inFlight` + `maxConcurrent = 3` | Avoid repeated probes on tab switches and bound concurrency. | **Pass by source/logic:** cache is session-global by server id; config changes with the same id can retain stale health until process/session reset. |
| 15 | Edit configuration | expected SET-05 edit action → no edit sheet or field-level config editor | Let users edit URL, command, args, env, headers, or transport. | **MISSING by feature scope:** no editable MCP configuration UI exists. |
| 16 | Install-set/bulk operations | expected SET-05 install-set action → no selection/batch model | Install, update, enable, disable, or remove multiple servers as a set. | **MISSING by feature scope:** no bulk selection or install-set action exists. |

## Confirmed defect and TDD evidence

### Silent MCP config mutations

`InstalledMCPRow.mutateConfig`, `setDisabled`, and `remove` previously used `guard`/`try?` and then called `onChanged` regardless of whether the config existed, the target was present, JSON encoding succeeded, or registry persistence succeeded. This could make the UI appear updated while the real configuration was unchanged or only half-mutated.

`MCPConfigMutationLogicTests` was written first. The red run failed because the mutation contract did not exist. The green implementation now parses and validates `mcpServers`, preserves sibling entries, throws a typed `MCPConfigMutationError` for invalid/missing targets, and encodes the result. `InstalledMCPRow` writes the tested output, updates the registry only after the config write succeeds, calls `onChanged` only after both steps succeed, and renders the localized error description inline on failure.

## Remaining limitations

SET-05 remains **PARTIAL**. There is no editable MCP configuration form, install-set/bulk management, or dedicated MCP library uninstall confirmation. The config-plus-registry update is still not transactional across a registry write failure after a successful config write; the UI now surfaces the failure instead of claiming success, but rollback is a future hardening candidate. Health caching is keyed by server id and may be stale if the same id’s endpoint changes during one app session. Live HTTP/stdio health, network/token fetching, SwiftUI rendering, and AppKit Settings interaction are unverified on Linux.

## Evidence and scores

| Check | Result | Boundary |
|---|---:|---|
| Red MCP mutation regression | **failed as expected** | Missing typed mutation contract |
| Green MCP mutation regressions | **3/3 passed** | Sibling preservation, missing-target failure, remove behavior |
| Full Foundation harness | **209/209 passed** | Existing contracts plus SET-05 regressions |
| Swift parser validation | **passed** | MCP mutation logic and MCP settings source |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| Native SwiftUI/AppKit interaction | **UNVERIFIED** | Requires macOS runtime |
| Live HTTP/stdio health probes | **UNVERIFIED** | Requires real MCP endpoints/processes |

The **implementation quality score is 93/100**. Silent mutation is fixed with a pure, tested contract and visible error path, but cross-store rollback, stale session cache invalidation, editable configuration, bulk actions, and live runtime checks remain.

The **task-following score is 100/100**. Every MCP button and function was traced, red tests preceded the confirmed fix, canonical documentation is being updated, and missing capabilities are marked honestly.

> An administrative action is not successful merely because a callback ran; success requires the persisted configuration, registry metadata, and visible state to agree.
