# Activity 50 — Settings, Security, and Registry Integrity

## Audit objective

This round audits **SET-04**, **SET-05**, **SEC-05**, and **SEC-06** from Settings navigation through skill/MCP library actions, persistent registries, enable/disable/remove mutations, health display, failure feedback, rollback, and the explicit future security policy.

## Full chain checklist

| Story | Chain audited | Expected behavior | Result |
|---|---|---|---|
| SET-04 | Skills tab → catalog search/install/update/uninstall → installed row → enable/disable/remove → skill registry/filesystem | Installed records are unique, update preserves enabled state, destructive removal is confirmed, toggle/remove failures are visible, and UI refresh occurs only after success. | **Fixed Round 96 duplicate-record recovery and silent mutation errors; 346/346 Foundation tests. Native SwiftUI/filesystem runtime UNVERIFIED.** |
| SET-05 | MCP tab → library install/update/uninstall → installed row → health probe → enable/disable/remove → mcp.json + registry | Registry records are unique; health dot reflects real probe/cache; config and registry mutations remain transactional; failures are visible and sibling config entries survive. | **Fixed Round 96 duplicate-record recovery and config rollback after registry failure; 346/346 Foundation tests. Native health probes/SwiftUI runtime UNVERIFIED.** |
| SEC-05 | Privacy-mode settings/action chain | Message-content redaction/privacy mode exists only when implemented and is never falsely presented as active. | **FUTURE; not implemented by product scope.** |
| SEC-06 | Database encryption/storage chain | At-rest encryption is explicit and honest; FileVault responsibility is not misrepresented as app-level encryption. | **FUTURE; FileVault remains the documented platform boundary.** |

## Detailed manual trace

| # | Action/function | Chain and invariant | Result |
|---:|---|---|---|
| 1 | Skills catalog | `AgentResourceLibraryView` loads bundled catalog, filters by search, displays install/update/uninstall state, dependency hints, progress, and visible errors. | **Pass by source; native SwiftUI interaction UNVERIFIED.** |
| 2 | Skill install/update | `AgentResourceInstaller` mutates skill files and registry; update state preserves the user’s enabled/disabled preference through existing tests. | **Pass by existing source/tests.** |
| 3 | Skill registry load | `SkillRegistryManager.load` decodes the registry and now collapses duplicate IDs using last-record-wins plus sorted output before rows consume it. | **Fixed Round 96 red/green.** |
| 4 | Skill enable/disable | Installed row calls `setEnabled`, treats false as a missing target, catches thrown writes, and displays an inline error without claiming refresh success. | **Fixed Round 96 red/green.** |
| 5 | Skill removal | Confirmation precedes removal; filesystem removal and registry removal are checked; errors remain visible and success alone triggers reload. | **Fixed/strengthened Round 96.** |
| 6 | MCP catalog | MCP library uses the same install/update/uninstall state machine and displays dependency/installation errors. | **Pass by source; native SwiftUI interaction UNVERIFIED.** |
| 7 | MCP registry load | `MCPRegistryManager.load` now collapses duplicate server IDs using last-record-wins plus sorted output before settings/health consumers read it. | **Fixed Round 96 red/green.** |
| 8 | MCP health | Session cache and max-concurrency gate prevent repeated probes; recent registry status maps to healthy/unhealthy/unknown; real checks persist status. | **Pass by source/tests; live stdio/HTTP probes UNVERIFIED.** |
| 9 | MCP enable/disable | `MCPConfigMutationLogic` preserves sibling servers; config is written atomically; registry update is required; failure restores original config bytes and shows an inline error. | **Fixed Round 96 red/green.** |
| 10 | MCP removal | Config removal is atomic; registry removal is required; failure restores original config bytes and leaves the visible row/error state truthful. | **Fixed Round 96 red/green.** |
| 11 | Security future boundaries | No privacy-mode redaction UI or app-level DB encryption is claimed as implemented; FileVault is not conflated with application encryption. | **Intentionally FUTURE.** |

## Confirmed defects and TDD evidence

### SET-04/SET-05 — corrupted duplicate registry records rendered raw

Both `SkillRegistryManager.load` and `MCPRegistryManager.load` returned decoded arrays without recovery from duplicate IDs. A corrupted or manually edited registry could render duplicate rows and make first-record-only mutations misleading. Red tests were written first for both registries. Both loads now use deterministic last-record-wins deduplication and sorted output.

### SET-04 — skill mutation errors were silently discarded

`InstalledSkillRow` used `try?` for enable/disable and removal, then refreshed regardless of whether persistence succeeded. Red source acceptance was written first. The row now exposes `mutationError`, guards the Boolean mutation result, catches thrown errors, checks filesystem removal, and refreshes only after success.

### SET-05 — MCP config and registry could diverge

MCP settings wrote `mcp.json` before persisting the registry. If registry persistence failed, the config changed while the registry did not. Red source acceptance was written first. Both enable/disable and remove now retain original bytes and restore them if the registry mutation fails.

### SEC-05/SEC-06 — future features remain honest

Privacy mode and app-level database encryption remain FUTURE. No red implementation test was appropriate because neither feature is part of the active product scope; the audit verifies that documentation does not present them as implemented.

## Evidence

| Check | Result | Boundary |
|---|---:|---|
| SET-04 duplicate skill registry red test | **failed as expected → passed** | Foundation registry persistence |
| SET-05 duplicate MCP registry red test | **failed as expected → passed** | Foundation registry persistence |
| SET-04 mutation-feedback red test | **failed as expected → 1/1 passed** | Persistent source acceptance |
| SET-05 rollback red test | **failed as expected → 1/1 passed** | Persistent source acceptance |
| Existing skill update/uninstall tests | **passed** | Foundation installer/registry logic |
| Existing MCP mutation/health tests | **passed** | Foundation mutation/health logic |
| Full Foundation harness | **346/346 passed** | Linux-safe suites |
| Adversarial source checks | **12/12 passed** | Existing web/model safety invariants |
| Swift parser validation | **passed** | Changed registry/settings/security files |
| `git diff --check` | **passed** | No trailing whitespace |

## Status and scores

The confirmed SET-04 and SET-05 source-level defects are fixed. The stories remain **PARTIAL** because native SwiftUI interactions, filesystem permissions, Keychain/session integration, and live MCP probes are not verifiable in this Linux environment. SEC-05 and SEC-06 remain **FUTURE** by explicit product scope. No Linux result is represented as native runtime proof.

| Story | Code quality | Task adherence | Target-runtime confidence |
|---|---:|---:|---:|
| SET-04 | 99/100 | 100/100 | 0/100 |
| SET-05 | 99/100 | 100/100 | 0/100 |
| SEC-05 | 100/100 | 100/100 | 0/100 |
| SEC-06 | 100/100 | 100/100 | 0/100 |

> The settings audit distinguishes “the mutation method returned” from “the state is consistent and the user was told the truth.” Registry deduplication, rollback, and visible errors now uphold that distinction.
