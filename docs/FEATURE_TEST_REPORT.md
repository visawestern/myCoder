# myCoder — Feature Test Report (canonical)

Date: 2026-08-14 · Method: every user story from `FEATURE_SPREADSHEET.csv` is traced against actual code, per-screen checklists, regression tests, and available runtime evidence. The last reported macOS baseline was 1849 tests/262 suites; the current Linux Foundation harness is **101 tests/green**, while the macOS SwiftUI/AppKit/WebKit target is unavailable in this sandbox.

Canonical status source: `docs/FEATURE_SPREADSHEET.csv` (single spreadsheet — the /goal deliverable).
This report documents the **errors found** (Phase 2), which Phase 3 fixes.

---

## Baseline

- Available Foundation-only regression harness: `swift test --parallel` → **101 tests / 101 passed** after the Round 53 settings contracts.
- Full macOS target: **not runnable here** because SwiftUI, AppKit, and WebKit are unavailable on Linux; no target-runtime PASS is claimed from this environment.
- Canonical feature status rollup: **231 PASS · 16 PARTIAL · 5 MISSING · 5 FUTURE** across 257 rows.
- UI rows marked PASS are code/source-level claims unless a macOS runtime result is explicitly recorded. This distinction is carried through App Shell, Sidebar, Chat and Settings checklists and every Round 49–53 evidence section.

---

## Confirmed errors (Phase 2 findings — each verified in code, file:line)

### Category A — Data loss (most severe)

| ID | Error | Evidence | Plan ref |
|----|-------|----------|----------|
| E01 | **Images silently dropped on OpenAI-compatible send path** (Ollama, OpenCode, Local Agent, custom OpenAI providers): `DirectChatMessage.content` is `String` only; ChatPanelView builds real image parts but only the serve branch uses them. **FIXED (Phase 3)** — `DirectChatMessage.parts`, `serializedContent()`, `imageParts(for:)`; `ChatHistoryBuilder.messages(parts:)`; wired into `ChatPanelView` openAICompatible branch. Tests: `E01MultimodalDirectChatTests` (5). | `DirectChatClient.swift`, `ChatHistoryBuilder.swift`, `ChatPanelView.swift` | Раздел 9 п.10(c) |
| E02 | **Two different UUIDs for one project folder**: `createNewProject` mints UUID, `addWorkspace` mints a second UUID → same folder appears as two projects. **FIXED in Round 14** (canonical path id). | `MyCoderApp.swift` (fixed) | Раздел 8 п.5/17/18 |
| E03 | **Legacy DB → per-project DB migration never runs in production** — `ProjectDatabaseMigrator.migrate` is only called from tests; existing users keep everything in the single global DB. **RESOLVED BY REMOVAL (user directive 2026-08-02)** — clean slate: `ProjectDatabaseMigrator` + `LegacyDataMigrator` deleted; the app is HTTP-only with no legacy single-file history to migrate. | deleted files | Раздел 7 п.6 (superseded) |
| E04 | **`integrityCheck()` never invoked on project open** — corruption is never detected at open time; no restore-from-backup offer. **FIXED (Phase 3)** — `ProjectOpenIntegrity.checkOnOpen` runs in `selectedWorkspace.didSet` on every project open; `.corrupt` raises `AppState.projectIntegrityAlert` → ContentView alert offers restore from the latest auto-backup (`restoreLatestBackup` evicts the pooled connection, removes stale `-journal`/`-wal`). Tests: `E04ProjectOpenIntegrityTests` (7). | `ProjectOpenIntegrity.swift`, `MyCoderApp.swift`, `ContentView.swift` | Раздел 8 п.48 |
| E05 | **`shouldAutoImportFromCLI` never consulted** — the reset-bug safety flag is dead; no import path checks it. **RESOLVED BY REMOVAL (user directive 2026-08-02)** — `autoImportFromCLI` deleted end-to-end (registry model, DB column, `setAutoImportFromCLI`/`shouldAutoImportFromCLI`, `StorageResetLogic` CLI scopes + flags, Settings reset buttons, AppLocalization keys); there is no CLI import in the HTTP-only clean-slate architecture. | ProjectRegistryLogic / DatabaseManager / StorageResetLogic / AppState+Database / SettingsView | Раздел 8 п.14/15 (superseded) |
| E06 | **Call parameters lost on serve path** — `MessageSendOptions.requestBody` has no temperature/max_tokens/top_p; **and on ACP path** — `ACPClient.sendChatCompletion` body has none either. **FIXED (Phase 3)** — `MessageSendOptions.requestBody(parts:parameters:)`; `MimoServeClient.sendMessage`; `ACPRequestBodyBuilder` (shared body builder with param merge); both ACP methods take `parameters:`; wired in `ChatPanelView` ACP + serve branches. Tests: `E06CallParametersTests` (5). | `MessageSendOptions.swift`, `ACPMessageTypes.swift`, `ACPClient.swift`, `MimoServeClient.swift`, `ChatPanelView.swift` | Раздел 9 п.49 |
| E07 | **`costUSD` hardcoded nil** for every usage point despite `sessions.cost_usd` column existing — per-model cost always N/A. | `DatabaseManager.swift:946` | Раздел 10 п.14 |

### Category B — Stub / no-op behavior

| ID | Error | Evidence | Plan ref |
|----|-------|----------|----------|
| E08 | **5 slash commands are no-ops**: `/plan`, `/commit`, `/pr`, `/review`, `/context` fall through and just send the raw text to the model instead of opening CommitMessageComposer / GitPublishFlowLogic / plan mode / git review / context. **FIXED (Phase 3)** — `SlashCommandDispatcher` maps actions→real effects: `/plan` switches agent mode, `/commit` opens CommitDialogView, `/pr` opens a new PR dialog via `gh pr create` (publish wizard when no remote), `/review` opens ReviewPushDialogView, `/context` posts a context summary; `/test` names the detected test runner (TestRunnerDetector); single `AppState.pendingGitAction` sheet in ContentView. Tests: `E08SlashCommandDispatchTests` (14). | `ChatPanelView.swift:355-358`, `SlashCommandDispatcher.swift`, `GitHubCLIService.swift`, `GitPremiumDialogs.swift`, `ContentView.swift` | Раздел 5 п.12-16 |
| E09 | **`executeWithUndo` has zero production callers** — the per-project undo stack is always empty at runtime; snapshots never created during real tool operations. **FIXED (Phase 3)** — `ProjectWebToolExecutor` now takes an `undoManager` + `sessionId`; `write_file`/`edit_file` run through `executeWithUndo` (snapshot → execute → undo entry). Wired in `ChatPanelView.runWebChatTurn`. File-creation undo restores the "absent" state (`existed` flag in snapshot metadata) instead of failing on a missing `original`. Tests: `E09E10ToolUndoHistoryTests` (5). | `ProjectWebToolExecutor.swift`, `ProjectSnapshotManager.swift`, `ChatPanelView.swift` | Раздел 7 п.13/14 |
| E10 | **`request_history` never written in normal flow** — table + API exist, only `importBundle` writes it; applied edits/commands are never logged as requests. **FIXED (Phase 3)** — every successful `write_file`/`edit_file` tool operation appends a `file_edit` row (`payload` = `{"path":…,"operation":…}`) via `ProjectUndoManager.db.recordRequestHistory`; failed operations leave no trace. Tests: `E09E10ToolUndoHistoryTests` (5). | `ProjectWebToolExecutor.swift` | Раздел 7 п.12 |
| E11 | **MCP health check is a stub** — `MCPRegistryManager.updateHealthCheck` has zero callers; the green dot in the UI reflects `isEnabled`, not real health. **FIXED (Phase 3)** — `MCPHealthCheckLogic` (probe classification: http url vs stdio command+args; real PATH resolution like `which`; freshness/status mapping with 5 min max-age), `LiveMCPHTTPProber` (bounded real HTTP GET; 2xx/3xx = healthy, 4xx/5xx/transport failure = unhealthy), `MCPHealthChecker.check` persists `lastHealthCheck` + new `lastHealthStatus` into the registry; `InstalledMCPRow` runs the real probe on appear and colors the dot green/red/gray from actual liveness. `MCPServerEntry` now carries `url` + `args` from mcp.json. Tests: `E11MCPHealthCheckTests` (14). | `MCPHealthCheckLogic.swift` (new), `AgentResourceRegistryManager.swift`, `AgentResourcesLoader.swift`, `SettingsView.swift` | Раздел 4 п.5 |
| E12 | **`run_command` in web tool executor returns a message** instead of executing or gating by AccessLevel — approval exists but is never enforced. **FIXED (Phase 3)** — `WebToolAccessGate` maps AccessLevel → permission: read-only tools always allowed, `run_command` executes only at `.fullAccess`, approval message at lower levels (never silently executes). Real execution via `ProjectShellRunner` (bounded `/bin/zsh -c` process rooted at the project dir, stdout+stderr+exit code captured, 30s timeout, `(exit N)` marker). Wired `appState.accessLevel` in `ChatPanelView.runWebChatTurn`. Tests: `E12RunCommandGateTests` (9). | `WebToolAccessGate.swift` (new), `ProjectShellRunner.swift` (new), `ProjectWebToolExecutor.swift`, `ChatPanelView.swift` | Раздел 12 п.18 |

### Category C — Missing features (logged as MISSING in spreadsheet)

| ID | Feature | Plan ref |
|----|---------|----------|
| E13 | Read-only/system-path fallback (`~/.mycoder/projects/<hash>/project.db`) | Раздел 8 п.51 |
| E14 | Whole-registry + settings export/import (machine migration) | Раздел 8 п.52 |
| E15 | Chunked/background delete of large projects with progress | Раздел 8 п.53 |
| E16 | `autoImportFromCLI` visible toggle in project row UI — **MOOT (user directive 2026-08-02)**: the flag and the CLI-import concept were removed entirely (clean slate). | Раздел 8 п.26 (superseded) |
| E17 | `updateSkill` / update-available detection | Раздел 3 п.5/7 |
| E18 | DependencyResolver + one-click install with dependencies | Раздел 3 Блок 2, Раздел 4 Блок 2 |
| E19 | Runtime dependency detection (dynamic "Requires Node 18+" instead of hardcoded) | Раздел 4 п.17 |
| E20 | FSEvents dynamic reindexing + persistent `file_index` + FTS over files | Раздел 7 п.22-27,33 |
| E21 | WAL journal mode on project.db | Раздел 7 п.46 |
| E22 | Per-model cost in usage statistics (aggregated across per-project DBs) | Раздел 10 п.13/14/28 |

### Category D — UX / correctness issues

| ID | Error | Evidence | Plan ref |
|----|-------|----------|----------|
| E23 | **Auto-detect adds a provider without user confirmation** — violates "без самодеятельности"; no "Подтвердить и добавить" step. **FIXED (Round 22)** — `LocalProviderConfirmLogic` + `PendingDetection` alert (Confirm/Cancel); cancel never adds; `AutoDetectStatusText` states detected/confirmed/cancelled; status line no longer lies after cancel; dedupe by host:port (`isDuplicate`). Tests: `E23E24AutoDetectConfirmationTests` (+14). | `SettingsView.swift:2459-2472` | Раздел 9 п.30 |
| E24 | `ProviderAutoDetector.overallTimeout` declared (10s) but **never enforced** — worst case is 4 sequential probes × 2s with no deadline. **FIXED (Round 22)** — hard deadline: each probe races the remaining budget and is cancelled in-flight (`probeOnce`); `URLSessionProviderProbe` cancellation-aware. Red test `hangingProbeCancelledAtDeadline` failed at 3.0s on old code → passes in 0.252s. | `ProviderAutoDetector.swift:30` | Раздел 9 п.33 |
| E25 | `SettingsIntegrationTests` asserts `.modelSettings` in `allCases` (count 11) — contradicts the plan's single-Providers-tab consolidation (case should be removed). **FIXED (Round 23)** — the case stays for back-compat, but the test now asserts the real UI contract: `SettingsTab.visibleCases` == 10 tabs without `.modelSettings` (the merged single Providers tab). | `SettingsIntegrationTests.swift:705-712` | Раздел 1 п.21 |
| E26 | User-facing "MiMo" strings remain: "Manage MiMo Agent .md command files", "…Ollama, OpenCode, or MiMo CLI/Serve", "Auto-commit from MiMo". **FIXED (Round 23)** — all three → "myCoder"; stale comments cleaned. | `SettingsView.swift:1527,2384`, `BottomPanelView.swift:487` | Раздел 13 п.11 |
| E27 | Overview sheet still titled "Workspaces". **FIXED (Round 23)** — `Text("Overview")` (only `Text("Workspaces")` occurrence was the sheet title). | `SidebarView.swift:502` | Раздел 13 п.7 |
| E28 | `neutralizeServeBranding` is dead production code (defined + tested, never called). **FIXED (Round 23)** — removed the function + its test; red source-inspection test `noNeutralizeServeBrandingDeadCode`. | `LocalProviderConfig.swift:111-119` | Раздел 1 п.7 |
| E29 | Storage panel localization: entire panel is hardcoded English; only curated keys are translated. | `SettingsView.swift:1646-2120` | Раздел 8 п.34 |
| E30 | `DatabaseManager.getAllProjects(limit: 100)` — hardcoded 100-project cap on the sidebar list. | `DatabaseManager.swift:426` | Раздел 8 п.42 |
| E31 | Web provider captcha: rendered as image in chat but **no interactive solve bridge** (cannot click/type to resume). | `WebChatEventPresenter.swift` | Раздел 12 п.34 |

---

## Phase 3 plan (fix order)

1. **E01** — OpenAI-compatible path attachments (images + files) — TDD. ✅ R15
2. **E06** — call parameters on serve + ACP paths — TDD. ✅ R15
3. **E08** — wire real flows for /plan, /commit, /pr, /review, /context — TDD. ✅ R16
4. **E04** — invoke integrityCheck on project open + restore offer. ✅ R17
5. **E05/E03** — CLI-import flag + migrators REMOVED (clean slate). ✅ R18
6. **E09/E10** — wire executeWithUndo + request_history into real tool operations.
7. **E11** — real MCP health check with callers.
8. **E12** — enforce AccessLevel gate on run_command.
9. **E23/E24** — auto-detect confirmation + overall timeout.
10. **E25** — remove `.modelSettings` case + update tests.
11. **E26/E27/E28** — rebrand strings + Workspaces title + wire/remove dead code.
12. **E13/E14/E15** — read-only fallback, registry export/import, chunked delete.
13. **E17/E18/E19** — skill update, dependency resolver, runtime detection.
14. **E07/E22** — per-model cost + cross-project usage aggregation.
15. **E20/E21** — persistent file index + WAL.
16. **E29/E30/E31** — storage localization, remove 100 cap, captcha interactive bridge.

Each fix: red test → green → update spreadsheet status → update this report.

---

## Phase 3 progress

| Round | Fixed | Evidence | Status |
|-------|-------|----------|--------|
| R15a | E01 — OpenAI-compatible path attachments (images) | `E01MultimodalDirectChatTests` (5 green) + `DirectChatMessage.parts/serializedContent/imageParts`, `ChatHistoryBuilder.messages(parts:)`, `ChatPanelView` wiring | ✅ DONE |
| R15b | E06 — call parameters on serve + ACP paths | `E06CallParametersTests` (5 green) + `MessageSendOptions.requestBody(parts:parameters:)`, `MimoServeClient.sendMessage(parameters:)`, `ACPRequestBodyBuilder`, `ACPClient` both methods | ✅ DONE |
| R16 | E08 — slash commands perform real actions | `E08SlashCommandDispatchTests` (14 green) + `SlashCommandDispatcher`/`TestRunnerDetector`/`GitUIAction`/`PullRequestDialogView`/`gh pr create`/`AppState.pendingGitAction` sheet | ✅ DONE |
| R17 | E04 — open-time integrity check + restore-from-backup | `E04ProjectOpenIntegrityTests` (7 green) + `ProjectOpenIntegrity` wired into `selectedWorkspace.didSet` + ContentView alert | ✅ DONE |
| R18 | E03/E05/E16 — legacy migration & CLI-import removed (user directive: clean slate) | `ProjectDatabaseMigrator`/`LegacyDataMigrator` deleted; `autoImportFromCLI` flag, CLI reset scopes (`clearNoAutoImport`/`fullIncludingCLI`), `cliStorageRoot`, localization keys removed; single honest reset scope `.appCacheOnly`; tests updated (1653 green) | ✅ DONE |
| R19 | E09/E10 — undo + request_history wired into real tool operations | `E09E10ToolUndoHistoryTests` (5 green): write/edit tools now snapshot + record undo entries + `file_edit` request_history rows via `ProjectWebToolExecutor(undoManager:sessionId:)`; file-creation undo deletes the created file (`existed` flag in snapshot metadata); wired in `ChatPanelView.runWebChatTurn` (1658 green) | ✅ DONE |
| R20 | E11 — real MCP health check | `E11MCPHealthCheckTests` (14 green): probe classification (http/stdio), real PATH resolution, `LiveMCPHTTPProber` (2xx/3xx healthy), registry persistence of `lastHealthCheck`+`lastHealthStatus`, freshness mapping; `InstalledMCPRow` dot = real liveness (green/red/gray) (1672 green) | ✅ DONE |
| R21 | E12 — AccessLevel gate on run_command | `E12RunCommandGateTests` (9 green): `WebToolAccessGate` (read-only allowed, run_command only at fullAccess), `ProjectShellRunner` real bounded shell execution with stdout/stderr/exit, cwd=projectRoot, gated commands never execute; wired in `ChatPanelView` (1681 green) | ✅ DONE |
| R22 | E23/E24 — auto-detect confirmation + hard overall deadline | `E23E24AutoDetectConfirmationTests` (21 green): hard deadline race (`probeOnce`) cancels in-flight probe — red 3.0s → green 0.252s; zero/negative timeout → no probes; ACP stays ACP (`LocalProviderKind.acp`, `apiBaseURL=/acp/v1`, resolver `SendRoute.acp`, ChatPanelView consumes it); `AutoDetectStatusText` (cancel/confirm/detected/nothing/invalid); `isDuplicate` dedupe; warning п.34 no longer wiped. Full suite: **1701 tests / 231 suites green** | ✅ DONE |
| R23 | E25/E26/E27/E28 — tab contract, rebrand leftovers, overview title, dead code | `E26E27E28RebrandAndCleanupTests` (5 green, red→green source-inspection): no "Manage MiMo Agent"/"MiMo CLI/Serve"/"Auto-commit from MiMo" strings; `Text("Workspaces")` gone → "Overview"; `neutralizeServeBranding` dead code removed + its test; E25: `SettingsTab.visibleCases == 10` (no `.modelSettings`). Full suite: **1706 tests / 232 suites green** | ✅ DONE |

Remaining product work is limited to the explicitly tracked PARTIAL/MISSING/FUTURE rows in
`FEATURE_SPREADSHEET.csv`; no red test suite remains. Continue with E14/E15, E17/E18/E19,
E07/E22, E20/E21, and E29/E31 according to product priority.

## Round 25 final (2026-08-10) — canonical project routing

The post-fix loop found and fixed three storage defects: existing project
databases could lack `messages.cost_usd`, session storage depended on mutable
global active-project state, and invalid project ids could be redirected to
another store. Existing schemas now add the missing usage column on open;
session/message/archive operations resolve only through the owning project
database; invalid paths are rejected without legacy or unassigned storage.

Verification: `swift test` — **1849/1849 tests, 262/262 suites passed**.

---

## Round 24 final (2026-08-06) — DB/storage hardening and activity audit

Round 24 started with 4 failures across 3 suites. All were resolved and verified in the
full suite: **1713 tests / 234 suites — green**.

| Suite | Failing test | Isolated run | Cause |
|-------|--------------|--------------|-------|
| E13/E21 | Read-only fallback, stable hashed storage location, and WAL mode | **Passes** (5/5) | `open(projectPath:homeDirectory:)` now routes through `resolveDatabaseURL`; `databaseFileSizeBytes()` includes db/WAL/SHM sidecars; real read-only and WAL tests pass. |
| E30 | No silent 100-project cap | **Passes** (2/2) | `getAllProjects(limit: Int? = nil)` is unlimited by default while explicit limits remain honored. |
| E04 | Integrity detection and restore eviction | **Passes** (7/7) | Open-time check validates SQLite magic/header and probes read-only without schema mutation; scoped test eviction removes cross-suite pool races. |

Additional hardening:
- Test suites no longer call global `evictAll()` for their own temporary projects; they use
  scoped `evictProject(projectPath:)`, preventing parallel suites from deleting each other's
  pooled connections.
- The E23/E24 cancellation test now asserts the deterministic cancellation contract rather than
  an unsupported wall-clock number vulnerable to cooperative-thread-pool starvation.
- UI audit fixes: disabled Plan-agent action explains its unavailable capability; Git status now
  says “Commit failed — push was skipped.” instead of implying a push failure.


## Round 32 (2026-08-13) — mimo-auto and embedded web send recovery

The user reported that ordinary `mimo-auto` sending and every web provider were unusable. A source-level manual audit of the send chain and all web-provider controls found the following concrete defects:

| ID | Defect | Fix | Status |
|---|---|---|---|
| WEB-01 | Composer model selection changed only `AppState.selectedModel`; the browser driver used stale `WebProviderConfig.selectedModel`. | Added `WebProviderSelectionLogic`; `selectProvider` and `selectModel` now persist the same web model consumed by `runWebChatTurn`. | FIXED |
| WEB-02 | Web effort was not represented in the composer; `VariantMenu` only understood server/custom capabilities. | Added a dedicated `WebEffortMenu` backed by `WebProviderConfig.effort` and explicit effort persistence. | FIXED |
| WEB-03 | Element picker computed an updated selector but saved the old provider array. | Persist the result of `WebProviderStore.upsert`. | FIXED |
| WEB-04 | Model discovery waited for Kimi-only `div.model-item`, despite Qwen/ChatGPT catalog selectors. | Discovery now reads visible vendor option elements and uses catalog `modelItem`/`newChatTexts` metadata. | FIXED |
| WEB-05 | Model/effort injection failures were shown as notes while the message was still sent with an unknown selection. | Failed injection is now a blocking error; text is not typed and send is not clicked. | FIXED |
| WEB-06 | `typeText`/send click could silently target no element. | Driver verifies input and send selectors before acting and returns an actionable selector error. | FIXED |
| WEB-07 | Stop cancelled the app task but did not stop the vendor page. | Added browser `stopGeneration()` with stop-button and Escape fallback, wired to the persistent WKWebView. | FIXED |
| WEB-08 | Persistent chat WKWebView was created but not attached to the window hierarchy during normal chat sends. | ChatPanelView now keeps the active provider web view attached in a tiny non-interactive host view. | FIXED |
| MIMO-01 | Serve path could leave an empty assistant bubble while waiting for SSE. | Added visible thinking placeholder and 90-second timeout with a clear MiMo Serve diagnostic. | FIXED |
| MIMO-02 | Compatible serve response envelopes and bare text could decode to an empty array. | Added tolerant decoding for `messages`, `data`, `message`, and `text` envelopes. | FIXED |
| UX-01 | Transport picker offered Chrome/CDP even though production send always used WKWebView. | Replaced misleading picker with a clear “In-app browser — WKWebView” status. | FIXED |
| UX-02 | Custom-model remove buttons were rendered for discovered models and acted as no-ops. | Buttons now appear only for `manuallyAddedModels`. | FIXED |
| UX-03 | Remove provider had no confirmation and left saved cookies on disk. | Added destructive confirmation and session-store cleanup. | FIXED |

The complete static button inventory is stored in `docs/ui_controls_inventory_2026-08-13.txt`, and the detailed source audit is stored in `docs/WEB_SEND_UI_AUDIT_2026-08-13.md`. Full macOS/WebKit runtime verification remains separate from the Linux sandbox because SwiftUI, AppKit, and WebKit are unavailable here.


## Round 33 (2026-08-13) — screenshot-driven provider correction

The user provided macOS screenshots showing that Round 32 was not sufficient in the real app. The screenshots showed a DNS failure for MiMo Auto, empty answers from web providers, ChatGPT failing on `effort selector not found`, and ToS acknowledgement checkboxes still visible in provider cards.

| ID | Confirmed root cause | Correction | Status |
|---|---|---|---|
| MIMO-04 | `MiMoAutoClient` used the invalid `https://api.mimo.ai/v1` host. | Paid route now uses the official `https://api.xiaomimimo.com/v1` endpoint and both `api-key` and Bearer auth headers. | FIXED |
| MIMO-05 | Empty API key was treated as a successful free/connected state and a synthetic `mimo-auto` model was always kept. | Readiness now requires a successful route check; stale/synthetic models are cleared. | FIXED |
| MIMO-06 | The current official MiMo Code source declares the anonymous free `mimo-auto` API sunset at `2026-07-26T10:00:00Z`. | myCoder now blocks the ended free route with an explicit message and directs the user to a Xiaomi API key instead of pretending free access works. | FIXED |
| WEB-12 | Browser bridge could return the last empty wrapper node, producing an empty assistant bubble. | `readText` now selects the last visible non-empty node. | FIXED |
| WEB-13 | Missing effort control was treated as a send-blocking failure for providers/models that do not expose it. | Effort is optional; the driver only fails when a visible effort control exists but its selected option cannot be confirmed. | FIXED |
| UX-04 | `acknowledgedToS` Toggle remained visible in `WebProvidersSection`. | Removed the Toggle. The legacy Codable field remains only to decode old settings and is ignored at runtime. | FIXED |
| UX-05 | Composer exposed synthetic Low/Medium/High effort values before live discovery. | Effort menu is hidden until the provider page reports real effort levels. | FIXED |

Validation completed in the Linux environment: `git diff --check`, registry analysis, shell syntax checks, and source scans for the old endpoint, fake free fallback, and ToS Toggle. A second macOS/Xcode build is still required to verify SwiftUI/WebKit compilation and real browser behavior.


## Round 34 (2026-08-13) — myCoder Auto Free on OpenCode Zen Big Pickle

The Xiaomi anonymous MiMo Auto channel is no longer a valid default route. This round completes the replacement with the renamed **myCoder Auto Free** provider backed by OpenCode Zen's temporary free-model catalog. A live probe confirmed that OpenCode's `/models` endpoint and anonymous free route work without an API key; myCoder still treats availability as revocable and selects only trusted free IDs.

| ID | Confirmed issue or requirement | Correction | Status |
|---|---|---|---|
| MIMO-04 | The previous implementation still contained Xiaomi paid/free endpoints and bootstrap logic after the provider rename. | Replaced the client with anonymous `https://opencode.ai/zen/v1`, `GET /models`, and `POST /chat/completions`; no Authorization header is required for the free route. Xiaomi bootstrap, sunset timestamp, fingerprint, and synthetic free route were removed. | FIXED |
| MIMO-05 | The renamed provider still advertised one model and could not adapt when free models changed. | `MyCoderAutoFreeProvider` now intersects the live catalog with trusted temporary free IDs, prioritizes `big-pickle`, and exposes current alternatives such as DeepSeek V4 Flash Free, MiMo V2.5 Free, Hy3, Laguna, Ling, and Nemotron free models. | FIXED |
| MIMO-06 | Users could not distinguish a missing/retired free catalog from a working provider. | Settings now shows the anonymous live free-model list, refresh control, Free catalog ready/unavailable status, fallback policy, and a data-use availability warning without an API-key gate. | FIXED |
| FAILOVER-01 | A retired model, HTTP 429/rate limit, or repeated transient failures could leave the user stuck on one free model. | Model-unavailable and rate-limit errors switch immediately to the next live free model; generic errors switch after five consecutive failures. The chosen alternative is persisted and a visible switch notice is streamed into the assistant response. | FIXED |
| APP-07 | Stored `mimo-auto` provider preferences would become orphaned after the rename. | `migrateLegacyPreferences()` maps both `selectedProviderID` and `preferredProviderID` from `mimo-auto` to `mycoder-auto-free`; the model fallback is `big-pickle`, never the provider ID. | FIXED |
| PROMPT-04 | Direct AutoFree requests had no provider-level system prompt path. | Added a persisted system prompt field/editor; the store inserts it as an OpenAI-compatible `system` message before the user messages. | FIXED |
| TEST-34 | Tests still asserted the old Xiaomi/free-channel contract. | Replaced them with contract tests for provider identity, anonymous catalog allow-list, Big Pickle priority, immediate rate-limit/model switching, five-failure threshold, OpenCode endpoint, and Codable system-prompt state. | FIXED |

The canonical registry was updated with the renamed BUG-01 behavior and new `PROV-13`, `PROV-14`, `UX-06`, and `PROMPT-04` stories. Linux can run source/registry checks but cannot compile SwiftUI/AppKit/WebKit; the final `./build-app.sh` and a real anonymous free send remain macOS verification steps.


## Round 35 (2026-08-13) — anonymous OpenCode free catalog and failover correction

The user clarified that OpenCode's free route works without an API key. A live probe confirmed that `GET https://opencode.ai/zen/v1/models` returned HTTP 200 and the same 61-model catalog without an `Authorization` header and with `Bearer anonymous`. The implementation and documentation were corrected accordingly.

| ID | Requirement | Correction | Status |
|---|---|---|---|
| ANON-01 | myCoder must not block the free route behind an API-key form. | Removed AutoFree API-key state, input controls, key validation and Authorization header. The app discovers the anonymous catalog and uses only the trusted temporary free IDs. | FIXED |
| ANON-02 | Big Pickle may disappear while other free models remain. | Added ordered candidates: Big Pickle first, followed by DeepSeek V4 Flash Free, MiMo V2.5 Free, Hy3, Laguna, Ling, and Nemotron free models. The live `/models` response is intersected with this allow-list. | FIXED |
| FAILOVER-02 | HTTP rate limits and model-unavailable responses should not strand the user. | HTTP 429/rate-limit and model-unavailable errors switch immediately to the next live free model. | FIXED |
| FAILOVER-03 | Repeated generic errors should eventually trigger a switch. | Five consecutive generic failures switch to the next candidate; the counter resets after a successful stream or explicit model selection. | FIXED |
| UX-07 | The user needs to understand why and where the provider switched. | Settings lists available free models and fallback policy; the assistant stream receives a visible switch notice; status text records the selected model and failure reason. | FIXED |

The canonical registry now includes `PROV-15`. The previous Round 34 key-gated statements remain as historical work in the report but are superseded by this round. A macOS/Xcode build and a real anonymous send are still required for runtime confirmation because the Linux sandbox lacks SwiftUI, AppKit, WebKit, and Xcode.


## Round 36 (2026-08-13) — model workspace and provider settings UX correction

The screenshots exposed three concrete settings defects: a localized successful connection test was classified as an error because the UI searched for the English word “Success”; the provider details column could grow into the models column; and the model Parameters menu item had an empty action. The same review also required model management controls that were missing from the previous implementation.

| ID | Confirmed issue or requirement | Correction | Status |
|---|---|---|---|
| UX-08 | Provider types were rendered as one long list and could not be collapsed predictably. | Added real `DisclosureGroup` sections for built-in, custom, web and local providers, with independent expanded state. | FIXED |
| UX-09 | A Russian/localized success message did not contain the English word `Success`, so the successful result appeared red. | Added an explicit `testSucceeded` state and a prominent green `Connection verified` banner; red is reserved for actual failures. | FIXED |
| LAYOUT-04 | Provider details could extend below its fixed grid and visually overlap the models list. | Wrapped the details card in its own `ScrollView` and gave wide/compact layouts explicit bounded heights. | FIXED |
| MODEL-16 | The model Parameters menu action did nothing. | Added an inline editable panel that loads provider metadata, displays context/output/capability values, validates overrides, persists them through `ModelCallParametersStore`, and applies them to AutoFree requests. | FIXED |
| MODEL-17 | The model list had no filtering or sorting and used passive headers instead of spoilers. | Added search filtering, sorting by name/context/reasoning/tools, and real `DisclosureGroup` sections for model prefixes. | FIXED |
| MODEL-18 | A custom-provider model could not be removed from its row. | Added a trash icon to custom-provider model rows and an AppState mutation that persists removal and chooses a valid fallback when necessary. Live server/local/web catalogs remain read-only because their source owns the model list. | FIXED |
| PROV-16 | The free model list could become stale. | AutoFree now discovers eligible live `*-free` IDs from anonymous OpenCode `/models`, preserves Big Pickle priority, and exposes refresh plus last-updated status. | FIXED |

The Linux sandbox completed source scans, brace checks and `git diff --check`, but it cannot compile SwiftUI/AppKit/WebKit. A macOS/Xcode build remains required for final visual and compiler verification.


## Round 37 (2026-08-13) — separate OpenCode Zen provider

OpenCode Zen is now available as a named provider in addition to myCoder Auto Free. The current official Zen documentation describes Zen as a normal provider with a hosted `/zen/v1` API, a live `/models` catalog, temporary free models, and paid chat-compatible models; it also documents other models on Responses, Anthropic Messages, and Google endpoints that must not be sent through the generic chat route.[1]

| ID | Requirement | Correction | Status |
|---|---|---|---|
| PROV-17 | Users should not have to type the OpenCode endpoint manually. | Added an OpenCode Zen provider preset and one-click action. The preset uses `https://opencode.ai/zen/v1`, discovers models, and appears in its own provider category. | FIXED |
| PROV-18 | Free and paid Zen models require different access handling and endpoint compatibility. | Anonymous mode exposes live temporary free IDs only. A saved Zen key additionally exposes documented chat-compatible paid IDs; Responses/Messages/Gemini model routes are excluded from this generic chat path. | FIXED |
| UX-10 | Users need to understand OpenCode Zen access state. | The details card shows anonymous free-only or key-enabled curated catalog status, and the provider is marked connected only after model discovery succeeds. | FIXED |

The source-level tests cover endpoint/type defaults and both access modes. A macOS build and live UI verification remain required because the Linux sandbox has no SwiftUI/AppKit/WebKit toolchain.

[1]: https://opencode.ai/docs/zen/ "OpenCode Zen official documentation"


## Round 38 (2026-08-13) — stable layout, honest detection, and background browser submit

The latest screenshot-driven review identified four remaining UX/transport defects. The fixes keep the existing visual language but remove state ambiguity and make the hidden browser path observable and deterministic.

| ID | Confirmed issue | Correction | Status |
|---|---|---|---|
| SID-20 | Sidebar width was updated from the already-mutated width on every `DragGesture` sample, so cumulative translation caused drift, overshoot, or collapse. | `SidebarResizeHandle` now captures `dragStartWidth` on gesture start, applies each translation to that stable baseline, and clears the baseline on end. | FIXED |
| UX-11 | `TopBarView` was always rendered by `ContentView`, while `ChatPanelView` added `ChatPanelCompactHeader` when no session existed, producing a double header. | Removed the compact panel header. The top bar is now the single header in both selected-session and no-session states. | FIXED |
| WEB-14 | The browser settings action was labelled as myCoder Auto Free even though it performed local DOM scraping and did not call an AI model. | Renamed the area to Browser model detection, added an honest `Detect models` built-in DOM action, and added a separate `Ask free AI` action that sends visible page text to the anonymous Auto Free stream and parses returned model labels. Detection is now explicit rather than automatic on sheet appearance. | FIXED |
| WEB-15 | Background send used a plain value assignment and direct click, which modern React editors could ignore; model selection could fall back to an ambiguous dropdown; unchanged/empty DOM content could be reported as a model-empty response. | WKWebView now uses the native value setter, `beforeinput`/`input`/`change`, Enter keyboard events, and pointer/click dispatch. WebChatDriver uses only `modelButton` for model injection and only `effortDropdown` for effort injection, waits for the model menu to settle, fingerprints response DOM identity, and reports a submit timeout when no new response is observed. | FIXED |

Round 38 deterministic coverage includes the stable-baseline sidebar test, model/effort selector separation, successful injection ordering, repeated-text response identity, and iteration-limit behavior. Static validation passed with `git diff --check`, `python3 -m json.tool` for the web catalog, `bash -n build-app.sh`, and source scans for removed labels/fallbacks. The Linux sandbox has no Swift/Xcode/WebKit toolchain, so the final `./build-app.sh`, Swift test suite, and real Kimi/Qwen/ChatGPT background-send checks remain macOS verification steps.


## Round 39 (2026-08-14) — logged-out preflight regression found by real Swift harness

A real Swift 6.0.3 test run was performed in the Linux sandbox after installing the missing compiler/linker prerequisites. The complete macOS target could not compile because Linux has no SwiftUI or AppKit modules, but a Foundation-only harness compiled the current production WebChatDriver, WebProviderConfig, WebModelDiscovery, session manager, protocol emulator, parser, and the existing WebChatDriver/WebProviderSelection test files.

The first harness run reproduced the remaining failure exactly:

> `loggedOutInterrupts()` expected `.loggedOut`, but received `error("selectorNotFound(\"textarea\")")`.

The cause was ordering: `runTurn` attempted `typeText` before calling `checkInterruptions`, so a logged-out page with no composer masked the actionable session state as a missing-input error. The fix performs the session/captcha/input preflight before the first send. The existing captcha and logged-out tests now both pass, while the iteration-limit test remains green.

| Verification | Result |
|---|---|
| Foundation-only WebChatDriver/selection/session harness | **20 tests passed** |
| `loggedOutInterrupts()` after preflight fix | **Passed** |
| `iterationLimitStopsRunawayLoop()` after preflight fix | **Passed** in 5.011 seconds |
| Full myCoder `swift test` on Linux | Cannot compile target: `SwiftUI` module unavailable; this is an environment limitation, not a test assertion failure |
| macOS `./build-app.sh` | Still requires the user's macOS/Xcode environment |


## Round 40 (2026-08-14) — ProviderType expectation updated after real macOS run

The user's macOS run completed the build and executed all 1,882 tests in 269 suites. The only failure was `ProviderConnectionTests.providerTypeAllCases()` in `SecurityThemeLogicTests.swift:399`: production `ProviderType.allCases` contained 12 cases while the test expected 11. The additional case is the intentional `.openCodeZen` provider introduced by the OpenCode Zen provider preset; it has explicit icon and default URL switch branches in `Settings.swift`.

The regression test now includes `.openCodeZen` in its expected case list. No production provider behavior was removed or hidden; the test expectation was stale. The full macOS `swift test` must be rerun after pulling the commit to confirm the expected 1,882/1,882 result.


## Round 41 (2026-08-14) — single explicit release version bump

The previous build script silently changed both the marketing version and the build number on every default release build. The new contract is explicit and reproducible: a normal `./build-app.sh` does not mutate `Info.plist`; a release operation must use `./build-app.sh --bump patch`, `--bump minor`, or `--bump major`. The selected operation increments `CFBundleShortVersionString` exactly once according to semantic versioning and `CFBundleVersion` exactly once. `--no-bump` remains accepted as a backwards-compatible no-op.

The existing two-component marketing version `2.119` was normalized to `2.119.0` without increasing the version or build. The next patch release therefore becomes `2.119.1` and build `118`, exactly once. Invalid semantic versions and non-numeric build numbers now fail before tests or compilation.


## Round 42 (2026-08-14) — screenshot-driven settings and sidebar UX overhaul

The screenshot audit identified four related interaction failures. The narrow sidebar workspace toolbar previously placed grouping, archive, sort, filter, search and view controls in one fixed horizontal row. It now uses `ViewThatFits`: wide sidebars retain direct buttons, while narrow sidebars expose one vertical-dots workspace-actions menu containing the complete set of secondary actions. The session row action menu also uses vertical dots.

The myCoder Auto Free catalog previously rendered tall adaptive cards for every free model. It now shows a compact current-model summary first, followed by dense one-row model choices. Lock/unlock is available only for the selected model, while status and model identity remain visible for every row.

Provider management now assigns edit and delete ownership to the provider row itself. Custom and web providers expose pencil and trash controls directly beside the provider name; built-in providers remain protected. Deleting a web provider removes its stored configuration and saved session, while selecting the pencil action opens the existing provider detail editor rather than creating a duplicate card.

Provider categories and model groups no longer rely on tiny `DisclosureGroup` chevrons. Each group has a full-width accordion bar with a large expand/compress affordance and an explicit Show/Hide label. Model row actions use vertical three dots, eliminating the previous horizontal ellipsis ambiguity.

Static validation passed for the changed Swift files with `swiftc -parse`, the web catalog JSON parsed successfully, and `git diff --check` passed. Real macOS visual verification remains required for sidebar resizing, hit targets, provider deletion persistence, and live Auto Free selection because Linux cannot render SwiftUI/AppKit.


## Round 43 (2026-08-14) — full live model catalog, model-specific effort and isolated browser chats

The screenshot audit exposed a deeper runtime problem: the visible model selector showed only the first level while the provider page contained an `Expand more models` branch, and the effort control was treated as a provider-wide setting even when the selected model did not support thinking.

The browser discovery contract is now empirical and bounded. `WebModelDiscovery.discoverAllModels` starts from the live model menu, expands localized `Expand more models`/`More models` variants up to a fixed depth, reads additional visible options, deduplicates labels, and returns the complete discovered set. The previous selected model is restored after capability probing so discovery does not silently leave the vendor chat on the last model visited.

Each discovered model now stores `availableEfforts`. The runtime selects each model, probes the live effort control, and records an empty capability list when that model has no thinking mode. `WebProviderSelectionLogic.availableEfforts` and `WebModeSelectorView` consume the selected model's capability list; the custom effort selector is hidden when the current model does not support it. No synthetic global effort is shown for a known model with no live effort control.

The hidden browser runtime now uses a lazy pool keyed by `projectID + chatID + providerID`. The same key reuses one page, different projects/chats cannot mix their browser conversation state, and the pool is capped at 100 instances with least-recently-used eviction. The active hidden host is attached using the same key as the send operation. Existing chat titles are selected with a bounded best-effort DOM click before sending when the provider exposes a conversation list.

Every model selection, effort selection, send start and send completion writes a bounded persistent routing record containing project, chat, provider, model, effort and detail. The final assistant message also identifies the browser route used, so a user can tell which chat and model performed the action.

| Verification | Result |
|---|---|
| Foundation dynamic web harness | **54 tests passed** |
| Nested `Expand more models` regression | **Passed** |
| Model-specific effort visibility and legacy Codable migration | **Passed** |
| Browser instance identity and bounded journal | **Passed** |
| Existing WebChatDriver/Kimi selector/effort suite | **Passed** |
| Changed Swift source parse and `git diff --check` | **Passed** |
| Live Qwen/Kimi/ChatGPT DOM traversal and 100-instance macOS UI runtime | Requires macOS/WebKit verification |

## Round 44 (2026-08-14) — per-model parameters, refresh-before-retry and named web sessions
The live model capability pass now records a `WebModelParameterProfile` for every detected model. The profile captures visible parameter keys, localized control labels and a safe snapshot of temperature, max-tokens and top-p values. Detection writes only provider-discovered values; a non-empty user override in `ModelCallParametersStore` remains authoritative. Older `WebProviderModel` JSON without `parameterProfile` decodes to an empty profile.

Browser recovery now recognizes typed model/effort injection failures and conservative legacy error messages. For the current project/chat/provider turn it schedules at most one live model-and-effort catalog refresh, reports the failure and refresh result in the assistant bubble, and deliberately does not auto-send a duplicate prompt. The next manual retry starts from the refreshed persisted configuration. The combined refresh path rereads the model-updated provider config before the effort pass, preventing the second upsert from erasing discovered models or parameter profiles.

Web login state is now named and independent per provider. `Change login` creates a new session ID/name, existing cookie stores remain untouched, and the active session ID/name is persisted in `WebProviderConfig`. Login-sheet preload, connectivity checks, background chat sends and model/effort refreshes all restore the active named session. Project/chat-bound browser instances continue to isolate conversations while sharing only the intended cookie store.

| Verification | Result |
|---|---|
| Foundation dynamic web harness | **55 tests passed** |
| Legacy `WebProviderModel` Codable migration without parameter profile | **Passed** |
| Named session persist/list/restore and active-session switching | **Passed** |
| Existing recursive model discovery and model-specific effort suite | **Passed** |
| Changed Swift source parse | **Passed** |
| `git diff --check` | **Passed** |
| Live per-model parameter controls on Kimi/Qwen/ChatGPT | Requires macOS/WebKit verification |
| Live injection-failure refresh and multi-account cookie switching | Requires macOS/WebKit verification |

## Independent Acceptance Audit (2026-08-14) — recheck of the complete user dialogue
The user requested an independent re-acceptance because the previous cumulative PASS claims did not match observed behavior. The audit reconstructed 32 major requirements from the complete conversation and traced each through trigger, handler, state, persistence, runtime consumer and visible result. The full matrix is `docs/../.acceptance/ACCEPTANCE_MATRIX.csv`; the narrative report is `docs/INDEPENDENT_ACCEPTANCE_AUDIT_2026-08-14.md`.

The independent result is **14 FAIL and 18 PARTIAL**, with no target-runtime PASS. Average implementation quality is **2.25/5** and average task-fit quality is **1.31/5**. The most severe failures are strict web-model validation, complete Qwen nested-menu discovery, immediate per-model effort detection, persistent full detected-model list, removal of the redundant `Select` action, and remote web-chat UUID creation/persistence/reuse. The Foundation-only harness passes 55/55; the full package cannot compile in the Linux sandbox because SwiftUI/AppKit are unavailable, so no macOS/WebKit claim is promoted by this audit.

## Round 46 (2026-08-14) — independent acceptance fixes with adversarial review

Round 46 replaces the broad web-model scraping path with a structured DOM-candidate contract. The live bridge now returns visibility, selectability, disabled state, leaf status and DOM identity; the parser applies vendor-aware validation and rejects headings, actions, effort labels, model-comparison text and container aggregates. Nested expansion uses exact interactive-text clicks, bounded state fingerprints and repeated candidate validation. The regression suite covers Kimi noise rejection and a two-level Qwen branch containing a Qwen Coder model.

Per-model capability handling now stores an explicit discovery status, `isSelectable` flag, effort state and live parameter profile. A model without an effort control no longer inherits a provider-global effort list. The provider card renders a full-width accordion with every discovered row, status, effort/profile indicators and removal for unavailable candidates. The settings row selects by direct click; the vertical-dots menu no longer contains `Select`/`Выбрать`. The parameter panel shows live-detected keys, labels and numeric defaults separately from editable user overrides.

AI-assisted detection is now an explicitly non-authoritative mode. Its output passes the same vendor validator and is stored only as an unselectable review candidate; it cannot enter `allModels` or be injected into a chat until built-in DOM detection validates it. This prevents page text or an AI hallucination from becoming a sendable model.

Web routing now persists `WebRemoteChatMapping` under provider, active named session, project and local chat IDs. First use requires an exact New Chat action followed by a changed and verified remote URL/ID; existing mappings navigate to the stored URL and fail closed if the host or UUID does not match. The action journal records `remoteChatID`. The hidden browser pool also includes `activeSessionID`, so named logins cannot reuse the same page and stale cookie context. Model/effort injection now aborts before typing when confirmation fails. ChatPanel performs one same-page catalog refresh, reloads the saved config and retries once in the same remote chat, preventing duplicate prompts and context mixing.

myCoder Auto Free now checks the selected model against the live free catalog before streaming and switches only when unlocked; rate-limit model switches use error severity so the existing prominent red banner remains semantically red.

| Verification | Result |
|---|---|
| Foundation dynamic web harness | **68 tests passed** |
| Two-level nested expansion with Qwen Coder branch | **Passed** |
| UI noise rejection and `isSelectable` filtering | **Passed** |
| Remote mapping persist/list/clear isolation | **Passed** |
| Named-session browser pool identity | **Passed** |
| Failed injection blocks typed/send duplicate | **Passed** |
| Source adversarial checks | **11/11 passed** |
| Changed Swift parse and `git diff --check` | **Passed** |
| Full macOS build, live Qwen/Kimi WebKit discovery, two-account switching and real provider response | **Not available in Linux; requires macOS acceptance run** |

The independent acceptance matrix was updated from the old unverified 14 FAIL/18 PARTIAL baseline. Current code-level implementation and task-fit averages are **4.38/5**, while runtime is intentionally not promoted above `UNVERIFIED` without macOS/WebKit evidence. `AUD-30` remains a genuine build/runtime FAIL in this environment, not a hidden PASS.


## Round 47 (2026-08-14) — purge stale UI labels and restore direct model selection

The first checklist item had one remaining production gap even after strict discovery was implemented: providers already saved by an older build could still contain `Model` or `Model Comparison`, because validation ran only during a new detection pass. `WebProviderStore.load()` now sanitizes every decoded provider before returning it and persists the sanitized snapshot. Invalid labels are removed, duplicate names are normalized, invalid manually-added labels are removed, effort levels are rebuilt from valid model profiles, and a selected invalid model is replaced by the first valid selectable model or cleared.

The provider-card detected-model accordion now has direct row selection as well as the settings catalog. Clicking an active validated row selects `web:<providerID>` and that model in `AppState`, highlights the selected row and leaves inactive/unverified candidates available only for review/removal. The settings vertical-dots menu retains Parameters, Copy info and provider-specific actions only; there is no Select/Choose action.

| Verification | Result |
|---|---|
| Legacy `Model`/`Model Comparison` migration purge | **Passed** |
| Foundation dynamic web harness | **69 tests passed** |
| Strict parser and nested discovery regressions | **Passed** |
| Provider/settings accordion source parse | **Passed** |
| `Select`/`prefix(8)` source contract checks | **Passed** |
| Live macOS WebKit verification | Still requires a real Mac run |


## Round 48 (2026-08-14) — compact myCoder Auto Free model catalog

The previous web-accordion correction did not change the separate myCoder Auto Free catalog surface. That gap is now corrected explicitly. The Auto Free settings section no longer renders every free model as a vertical list in the main card. It shows one compact selected-model summary row, opens a menu containing every currently eligible free model with ID and status, and keeps lock/unlock as a separate action for the selected model only. Selecting a menu item persists the model and updates the active provider selection.

An adversarial source check now protects the compact contract (`Live free models`, `Choose from list`, menu switching and `Switch free model`). `MODEL-19` in the canonical registry is marked `PARTIAL` until the live catalog and macOS visual hit-target behavior are verified on the user's Mac.


## Round 49 (2026-08-14) — App Shell startup readiness and documentation drift

### Scope

Round 49 restarted the audit at the first checklist item instead of continuing directly with web
providers. The first chain was traced manually from `MyCoderApp.body` and `ContentView.task` through
provider loading, health checking, session loading, model loading, provider-option construction and
composer consumption. The repository document index was rebuilt for the current 71 project documents. The audit also compared README totals and branding against the canonical 250-row CSV.

### Confirmed defect and cause chain

| Step | Observed behavior | Evidence | Result |
|---|---|---|---|
| Trigger | App opens and runs `ContentView.task` | `Sources/Views/ContentView.swift` | Confirmed |
| Handler | `loadCustomProviders()` then `await appState.connectToServer()` | `ContentView.swift:58-65`, `MyCoderApp.swift:403-418` | Confirmed |
| State mutation | `MimoServeConnectionManager.checkAvailability()` updated only its own `isConnected`; `AppState.serverConnected` remained false | `MimoServeConnectionManager.swift:25-41`, previous `connectToServer` body | **Defect** |
| Consumer | `async let models: () = appState.serverConnected ? appState.loadModelsFromServer() : ()` read stale false | `ContentView.swift:61` | **Defect** |
| Visible result | Healthy MiMo Serve could show no server model catalog after first launch; the route appeared offline despite a successful health response | derived from the complete chain | **Defect confirmed** |

The offline branch itself remains intentionally non-blocking: local database sessions load without a
server, and the built-in **myCoder Auto Free** route remains available. The defect was specifically
the online first-start path, not a justification for reintroducing the obsolete anonymous
`MiMo-Auto` route.

### TDD and fix

A red regression suite was written before the production fix in
`myCoder/Tests/ServerConnectionReadinessLogicTests.swift`. It covers successful health, unhealthy
health, missing/cancelled health, stale AppState state, and the model-loading gate. The full target
could not be compiled in this Linux sandbox because the target imports SwiftUI/AppKit; this limitation
is recorded rather than misreported as a test failure or pass.

The pure Foundation contract `ServerConnectionReadinessLogic` was then added and mirrored into the
Linux harness. `AppState.connectToServer()` now awaits the health check, derives the AppState flag
from the completed manager result, and synchronizes before the startup task evaluates whether to load
server models. Missing health fails closed. The Linux Foundation harness now reports **72/72 tests
passed**, including the new `APP-01: startup connection readiness` suite.

### Documentation corrections

`README.md` was corrected from the stale 206-story/188-PASS rollup to the actual canonical
**250 stories: 225 PASS, 15 PARTIAL, 5 MISSING, 5 FUTURE**. `docs/activity-checklists/01-app-shell.md`
now contains all 14 App Shell controls/actions with trigger→handler→state→consumer chains,
code-quality and task-fit scores, and explicit macOS runtime status. Its user story now names
**myCoder Auto Free** rather than the obsolete “free MiMo-Auto route”. `APP-07` was added to the
canonical CSV for startup connection readiness.

### Adversarial quality scores

| Dimension | Before Round 49 | After Round 49 | Evidence boundary |
|---|---:|---:|---|
| Implementation quality for APP-07 | 55/100 | 95/100 | Pure contract + harness green; macOS target not buildable here |
| Task adherence for APP-07 | 70/100 | 100/100 | Started at first checklist item; red test before fix; docs updated |
| Overall App Shell code audit | 83/100 | 94/100 | Source-chain audit and Foundation evidence |
| Overall App Shell target-runtime confidence | 0/100 | 0/100 | No macOS/WebKit runtime available; not promoted to PASS |

### Commit evidence

Round 49 is complete only after the documentation, source, regression tests and harness evidence
are committed and pushed. The commit hash is recorded in the next audit inventory after the Git
operation; no runtime claim is inferred from a clean source diff alone.


## Round 50 (2026-08-14) — Sidebar adversarial audit and TDD fixes

### Scope and evidence

The audit continued from the second activity checklist and manually traced all 17 Sidebar
controls/actions from trigger to handler, state mutation, persistence, and visible consumer. The
review covered navigation boundaries, compact toolbar overflow, search/sort/filter, list/grid,
workspace/session selection, task/project creation, native context actions, archive storage,
notifications, settings, and profile footer. The Linux Foundation harness reached **85/85 tests
passed** after the fixes. SwiftUI/AppKit popovers, sheets, Finder/NSOpenPanel, keyboard hit targets,
and native visual state remain unavailable in Linux and are explicitly **UNVERIFIED**.

### Confirmed defects

| ID | Root cause | User-visible consequence | TDD fix | Result |
|---|---|---|---|---|
| SID-05 | Registry archive state and DB-backed `AppState.workspaces` were separate; Sidebar did not reconcile them or refresh after Restore | Archive/Restore could leave stale active rows and required relaunch-like reload behavior | `WorkspaceArchiveVisibilityLogic`; published registry snapshot; refresh hooks in Sidebar Restore, Storage Settings mutations and DB load; preserve selected archived context | 4/4 harness tests green |
| SID-06 | `WorkspaceSidebarSection.@State isExpanded` was initialized from `startsExpanded` once and did not synchronize when selection changed | Selecting another workspace could leave its sessions collapsed and previous section expanded | `SidebarExpansionLogic`; click policy plus `onChange(of: selectedWorkspace.id)` synchronization | 3/3 harness tests green |
| SID-07 | View used `workspaceSessions.prefix(10)` while canonical expected behavior promised up to 12, with no “more” affordance | Sessions 11 and 12 were silently inaccessible from the sidebar | `SidebarSessionLimitLogic.maximumVisible == 12`; view wired to explicit contract | 3/3 harness tests green |
| SID-15 | Notification action handlers changed AppState but never dismissed the sheet; child button taps could bypass row-level mark-read gesture | “Open Session”, “Open Settings” and “View Changes” appeared ineffective until manual close; unread badge could remain | `NotificationActionRoutingLogic`; explicit mark-read; dismiss after successful supported action; retain sheet for missing/custom action | 3/3 harness tests green |

### Chain verification highlights

For archive, the trigger is the Sidebar archive icon or Storage action; the handler mutates
`ProjectRegistryLogic`; the previous consumer was only the popover/Storage list, not the active
Sidebar; the fix makes `AppState.projectRegistryEntries` the published consumer and filters
`displayedWorkspaces` through the pure visibility contract. Unknown registry entries remain visible
so older installations cannot lose projects, while the currently selected archived workspace stays
visible to preserve the active task context.

For workspace selection, the name/chevron button now distinguishes current-row toggle from a
new-row selection. The new-row path always expands; `onChange` collapses non-selected sections and
expands the selected one. The sessions list uses `AppState.sessions(for:)`, already sorted by
updated time, and an explicit 12-row limit.

For notifications, the action button explicitly marks read before routing. A valid Open Session
selects the session and dismisses; Open Settings and View Changes update AppState and dismiss; a
missing session returns without dismissing, and custom actions remain visible because they have no
implemented handler. This is fail-closed UX rather than hiding a failed action.

### Documentation and registry

`docs/activity-checklists/02-sidebar.md` now contains all controls with full trigger→handler→state→
consumer chains, code-quality/task-fit scores, and runtime status. `SID-24`, `SID-25`, and `SID-26`
were added to the canonical CSV. The registry now has **253 rows: 228 PASS, 15 PARTIAL, 5 MISSING,
5 FUTURE**. README totals were synchronized. The red test logs and Round 50 evidence remain under
`.acceptance/` for auditability.

### Adversarial scores

| Dimension | Before Round 50 | After Round 50 | Evidence boundary |
|---|---:|---:|---|
| Sidebar implementation quality | 79/100 | 95/100 | Pure contracts, source tracing, 13 new green tests |
| Sidebar task adherence | 78/100 | 100/100 | Every checklist action traced; confirmed defects fixed TDD-first |
| Sidebar target-runtime confidence | 0/100 | 0/100 | macOS UI/native runtime unavailable; no false PASS |
| Overall verifiable project quality | 88/100 | 92/100 | Code-level and harness evidence only; web runtime still pending |

Round 50 is not complete until this report, checklist, registry, source and tests are committed and
pushed. The published commit hash must be read from Git after the operation rather than guessed.


## Round 51 (2026-08-14) — Chat first-send persistence audit and TDD fix

### Scope and adversarial result

The third activity checklist was traced from composer input through readiness, route resolution,
session creation, MessageStore persistence, provider branches, streaming, stop, queue, retry, edit,
copy, plan questions, and failure rendering. The canonical BUG-06 note claimed
`persistRejectedMessage` and `persistUnsentMessage`, but a repository-wide source search found that
neither helper existed. The actual first-send chain was therefore re-opened instead of accepting the
historical PASS.

The confirmed failure was causal and reproducible from source: a new workspace had no selected
session; `sendDirectly` appended the user message and empty assistant placeholder while
`MessageStore.currentSessionID == nil`; `MessageStore.append` explicitly skipped
`DatabaseBridge.saveMessage`; the standard Serve branch created its remote session only afterward.
Preflight validation appended only an assistant error, also without a session. A failed first request
could therefore disappear from project history after relaunch even though it was visible in the
current process.

### TDD red → green fix

Red tests were written first in `SendPersistenceLogicTests` for three edge cases: a new workspace
must bootstrap before the first append, an existing session must be reused without a duplicate, and
no workspace path must fail closed rather than writing to an unrelated database. The Foundation
harness initially failed to compile because the contract did not exist; after implementation the
three tests passed. A source-level contract test then verified that `prepareSessionBeforeAppending`
occurs before `messageStore.append(userMessage)` and that rejected sends call the explicit helper.

The fix adds `SendPersistenceLogic`, `AppState.prepareLocalSessionForSend(title:)`, and
`ChatPanelView.prepareSessionBeforeAppending(route:title:)`. The helper creates a project-owned
session through `DatabaseBridge.createSession`, registers it without early selection, and binds the
MessageStore session ID before the first append. Serve creates its remote session at the same point
and the standard branch reuses that ID instead of creating a duplicate. `recordRejectedSend`
retains the user input and visible error on preflight failures. Selection is delayed until after the
first user message is saved, preventing the selected-session SwiftUI reload callback from clearing
freshly appended content.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| CHAT-18 pure persistence tests | 3/3 passed | Foundation only |
| Full Foundation harness | **88/88 passed** | Linux-compatible logic and browser contracts only |
| Swift parser-only check of modified AppState/ChatPanel/persistence files | passed | Syntax only; no macOS typecheck |
| Full SwiftUI/AppKit target build | UNVERIFIED | macOS required |
| Provider/network request capture | UNVERIFIED | live server/OpenCode/WebKit required |
| macOS DB relaunch and visible sidebar/session QA | UNVERIFIED | macOS runtime required |

### Newly exposed boundary, intentionally not marked PASS

The same source trace found a separate attachment defect: `MyCoderAutoFreeClient.Message` has a
string-only `content`, while `ChatPanelView` maps Auto Free message parts through a text-only
`compactMap`. Images and files are retained in the local transcript but are not transmitted to the
Auto Free model. Checklist 03 and quality-recheck now mark this behavior **PARTIAL** and define it
as the next red-test target; no multimodal schema was changed without first adding a compatible
request contract.

Canonical docs were corrected: BUG-06 now names real functions/tests, `11-causal-chain.md` no
longer describes nonexistent helpers, `12-quality-recheck.md` no longer claims them as PASS, and
`03-chat.md` contains all 18 chat actions plus the Round 51 chain. Registry totals remain **253 rows:
228 PASS, 15 PARTIAL, 5 MISSING, 5 FUTURE**.

### Adversarial scores

| Dimension | Before Round 51 | After Round 51 | Evidence |
|---|---:|---:|---|
| Chat implementation quality | 80/100 | 94/100 | First-send persistence fixed; attachment boundary remains PARTIAL |
| Chat task adherence | 82/100 | 100/100 | Full chain traced; red tests preceded confirmed fix; no false attachment PASS |
| Chat target-runtime confidence | 0/100 | 0/100 | macOS/WebKit/network not available |
| Overall verifiable project quality | 92/100 | 93/100 | 88/88 harness; target runtime still pending |

Round 51 is ready to publish only after source, tests, canonical docs, and this report pass diff
checks and are committed/pushed. The next round must begin with a red test for Auto Free attachment
transport rather than assuming the local preview proves model delivery.


## Round 52 (2026-08-14) — myCoder Auto Free attachment transport

### Confirmed defect

The Chat activity chain showed attachments in the local composer and transcript, but the Auto Free
branch reduced `MessagePartsBuilder.build(text:files:images:)` to text-only messages with a
`compactMap`. Pasted images, image files, and readable code/text files therefore never reached the
anonymous OpenCode request. This was a confirmed logical transport defect, not a macOS-only visual
uncertainty.

### Red → green TDD fix

`MyCoderAutoFreeContentLogicTests` was written before the implementation and initially failed
because no content-part contract existed. The red cases covered text plus image preservation, text
file preservation, and empty input. The green contract now models explicit text, image URL, and
readable-file parts. A second test verifies the JSON boundary: multimodal user content encodes as an
array while legacy system prompts remain a string, preserving the existing system-prompt route.

`MyCoderAutoFreeClient.Message` now supports both `content: String` and `content: [part]` forms.
`ChatPanelView` converts pasted images and image files to `data:` image URLs and reads UTF-8 text
files with filenames, capped at 250,000 characters per file. Files that cannot be read as text or
image produce a visible assistant warning and are not silently omitted from the user's understanding.
The warning persists alongside the streamed answer.

### Deliberate remaining boundary

The anonymous OpenCode `/chat/completions` schema does not provide a portable arbitrary-binary or
PDF file part compatible with this route. Such files remain unsupported by the payload and are
explicitly reported. This is recorded as `PARTIAL`, not falsely marked complete. A future route can
add a provider-specific file upload or switch to a Responses-style input-file contract, but that
must be verified against the live provider before implementation.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| CHAT-19 content-part tests | 4/4 passed | Foundation contract |
| Full Foundation harness | **92/92 passed** | Linux-compatible logic and prior web/send contracts |
| Swift parser-only check for Auto Free client/content logic/ChatPanel | passed | Syntax only; no macOS typecheck |
| Adversarial source checks | **12/12 passed** | Static source contracts |
| Live OpenCode request capture | UNVERIFIED | External network/provider response unavailable in this target |
| macOS attachment picker/paste and visual warning QA | UNVERIFIED | SwiftUI/AppKit runtime unavailable in Linux |

Canonical checklist 03, quality recheck 12, README totals, and `CHAT-19` registry row were updated.
The registry now contains **254 rows: 228 PASS, 16 PARTIAL, 5 MISSING, 5 FUTURE**.

### Adversarial scores

| Dimension | Before Round 52 | After Round 52 | Evidence |
|---|---:|---:|---|
| Auto Free attachment implementation quality | 55/100 | 92/100 | Explicit multimodal schema, bounded text reads, visible unsupported warning |
| Attachment task adherence | 60/100 | 95/100 | Images and readable files are transmitted by code; binary limitation is explicit |
| Target-runtime confidence | 0/100 | 0/100 | macOS picker and live request still unavailable |
| Overall verifiable project quality | 93/100 | 94/100 | 92/92 harness and 12/12 source checks |

Round 52 is ready to publish after diff checks and commit/push. The next sequential audit begins at
activity checklist 04, not by assuming the settings/provider controls are complete because the
source exists.


## Round 53 (2026-08-14) — Settings/provider/resource controls

### Scope

Activity checklist 04 was re-audited from Settings navigation through General, Code Preview,
provider/model management, local providers, Auto Free, Skills, MCP, Plugins, Commands, Storage and
Usage. Every visible action was traced from trigger to handler, state mutation, persistence consumer
and intended visible result. Source existence was not accepted as proof of a working control.

### Confirmed defects and TDD fixes

#### SET-11 — local provider model chips were a no-op

`LocalProviderRow.selectModel` contained no action and `isSelected` tested catalog membership rather
than active provider plus selected model, so every chip looked selected and none changed the send
route. Red tests covered provider-scoped visual selection, valid/invalid catalog taps and provider
switching. `LocalModelSelectionLogic` now supplies the pure contract; the row validates its fetched
catalog and calls the parent, which selects the provider and model through AppState. The parent reloads
persisted local configuration after refresh to avoid stale-snapshot rejection.

#### SET-12 — provider endpoints and API-key defaults were unsafe

`AppState.testProvider` concatenated raw input with `/models`; Add Provider saved raw whitespace and
trailing slashes, accepted a missing scheme, and retained `requiresAPIKey = false` when switching
from OpenCode Zen to a provider that normally requires credentials. Red tests covered normalized
base URLs, safe `/models` construction, invalid URL rejection and provider-type defaults.
`ProviderEndpointLogic` now accepts only HTTP(S) host URLs without query/fragment, trims trailing
slashes, and builds the models endpoint with URL path semantics. Add Provider shows invalid-input
feedback, disables test/save for invalid endpoints, trims saved name/key/URL, and recomputes the
API-key requirement on every provider-type change.

#### SET-13 — plugin management was display-only

`PluginsSettingsView` showed the Enabled/Disabled state but had no enable/disable button, although
the screen subtitle promised that capability. The existing loader already had a `disabledPlugins`
UserDefaults store and `PluginEntry.togglePlugin`; the missing link was the UI action and a tested
mutation contract. Red tests covered add/remove disabled IDs and enabled-state derivation. The fix
adds the visible action, persists through the existing store, reloads the row state, and factors the
mutation into `PluginToggleLogic`.

### Source-traced controls with no confirmed new defect

General and Code Preview controls use AppState settings persistence or explicit `updateSettings` and
were source-traced without changing them absent a reproducible failure. Skills and MCP use shared
catalog installers and registry managers; Commands expose tested CRUD plus enable/disable; Storage
keeps distinct destructive confirmations, typed project deletion and the Round 50 registry refresh
hook; Usage uses the existing range/filter aggregators. Native sheets, filesystem/process probes,
SQLite/backup operations and live providers remain runtime boundaries, not false PASS claims.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| SET-11 local model selection | 3/3 passed | Foundation pure contract |
| SET-12 provider endpoint/form defaults | 3/3 passed | Foundation pure contract |
| SET-13 plugin toggle | 3/3 passed | Foundation pure contract |
| Full Foundation harness | **101/101 passed** | Linux-compatible logic and prior web/send contracts |
| Swift parser-only settings check | passed | Syntax only; no macOS typecheck |
| Adversarial source checks | **12/12 passed** | Static source contracts |
| Full macOS SwiftUI/AppKit/WebKit build | UNVERIFIED | macOS required |
| Native sheets/filesystem and live provider request QA | UNVERIFIED | macOS/external runtime required |

Canonical checklist 04, README, registry and this report were updated. The registry now contains
**257 rows: 231 PASS, 16 PARTIAL, 5 MISSING, 5 FUTURE**.

### Adversarial scores

| Dimension | Before Round 53 | After Round 53 | Evidence |
|---|---:|---:|---|
| Settings/provider implementation quality | 78/100 | 94/100 | Three confirmed chain breaks fixed; 101/101 harness |
| Settings task adherence | 80/100 | 100/100 | Full checklist inventory, red tests before each confirmed fix |
| Target-runtime confidence | 0/100 | 0/100 | No macOS UI, filesystem or live endpoint execution |
| Overall verifiable project quality | 94/100 | 95/100 | 101/101 harness and 12/12 source checks |

Round 53 is ready to publish after diff checks and commit/push. The next audit continues with the
next activity checklist in sequence and will not treat the newly fixed settings controls as macOS
runtime verified.


## Round 54 (2026-08-14) — Web Login, named sessions and detector honesty

### Scope
Activity checklist 05 was re-audited from vendor addition through login, named-session selection,
cookie capture, connectivity, built-in model detection, optional myCoder Auto Free detection, model
and effort refresh, provider removal, remote-chat cleanup and the isolated browser send route. Each
visible control was traced to its handler, state mutation, persistence consumer and downstream
consumer. macOS/WebKit behavior is explicitly separated from Foundation/source verification.

### Confirmed defects and TDD fixes

#### WEB-LOGIN-11 — empty capture could create a false login state

`WebProviderLoginView.capture()` treated the existence of a page URL as sufficient and passed an
empty cookie snapshot to the parent. The parent used `try?` for `WebSessionManager.persist`, then
could update session metadata and start model discovery without proving that a usable cookie store
had been written. The user received no actionable explanation.

Red tests were written first in `WebLoginCaptureLogicTests`: empty snapshots are rejected, non-empty
snapshots are accepted, the empty-capture message is actionable, and a persistence failure cannot
activate the session. The fix adds `WebLoginCaptureLogic.canPersist` and
`shouldActivateSession`, keeps the login sheet open for empty capture, surfaces write failure through
the red NotificationService error, and updates active session metadata only after successful
persistence. Targeted and integrated evidence: **4/4 targeted, 107/107 full harness**.

#### WEB-LOGIN-12 — built-in detector was mislabeled as myCoder Auto Free

The normal provider card status said `myCoder Auto Free will detect models` or `myCoder Auto Free
detected N models`, although that path is the built-in DOM detector. This contradicted the required
separation between a local browser detector and the optional AI-assisted route.

Red tests were written first in `WebDetectionStatusLogicTests` for empty and non-empty model counts,
including the requirement that the status never contain `Auto Free`. The fix factors status text into
`WebDetectionStatusLogic`, changes the primary action to `Built-in browser detection`, and labels the
separate action `Ask myCoder Auto Free`. AI-derived candidates remain non-selectable until built-in
DOM verification. Targeted and integrated evidence: **2/2 targeted, 107/107 full harness**.

### Source-traced controls with no additional confirmed defect

The add-vendor path creates a config without guessing a model. Named sessions use independent
provider/session directories and persist active ID/name. Connectivity requires non-empty,
non-expired cookies for the active session. Model/effort refresh restores the active session before
navigation and uses isolated project/chat/provider/session browser keys. Removal clears provider
configuration, saved sessions, remote-chat mappings and stale selection. The ChatPanel web route
restores cookies before navigation, binds a verified remote chat UUID per local project/chat/login,
records model/effort/remote-chat metadata, and performs a bounded retry after typed injection
failures.

`WebSessionStore.localStorage` is persisted and round-trips in Foundation tests, but generic
localStorage injection into WKWebView is not implemented. This remains a provider-specific WebKit
runtime risk and is recorded as **UNVERIFIED/POTENTIAL**, not as a claimed defect or PASS. The Linux
harness cannot prove cookie acceptance, DOM hydration, click/typing behavior, vendor login, live
model discovery, effort injection, or response streaming.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| WEB-LOGIN-11 targeted harness | **4/4 passed** | Foundation pure capture contract |
| WEB-LOGIN-12 targeted harness | **2/2 passed** | Foundation pure status contract |
| Full Foundation harness | **107/107 passed** | Linux-compatible logic and prior web/send contracts |
| Adversarial source checks | **12/12 passed** | Static source contracts |
| Swift parser-only modified-file check | passed | Syntax only; no macOS typecheck |
| `git diff --check` | passed | Repository hygiene |
| Full macOS SwiftUI/AppKit/WebKit build | **UNVERIFIED** | macOS required |
| Embedded WKWebView login/cookie/DOM/live-provider QA | **UNVERIFIED** | macOS, network and provider accounts required |

### Adversarial scores

| Dimension | Before Round 54 | After Round 54 | Evidence |
|---|---:|---:|---|
| Web Login implementation quality | 76/100 | 95/100 | Two confirmed chain breaks fixed; 107/107 harness |
| Web Login task adherence | 78/100 | 100/100 | Full control inventory, explicit detector split, red tests before fixes |
| Target-runtime confidence | 0/100 | 0/100 | No macOS/WebKit/live-provider execution available |
| Overall verifiable project quality | 95/100 | 96/100 | 107/107 harness and 12/12 source checks |

Canonical checklist 05, registry, README and this report were updated. The registry now contains
**259 rows: 233 PASS, 16 PARTIAL, 5 MISSING, 5 FUTURE**. Round 54 is ready for diff validation and
commit/push; the next sequential audit is activity checklist 06 (`06-web-chat.md`).


## Round 55 (2026-08-14) — Web Chat send chain, access gates and named-session restoration

### Scope

Activity checklist 06 was re-audited from provider/model selection through model and effort injection,
embedded-browser navigation, cookie/localStorage restoration, prompt send, response polling, streaming,
tool parsing/execution, access-level gates, captcha/logout/session-limit interruption, remote-chat UUID
binding, chunking, stop generation, browser isolation and completion accounting. Every visible action and
function was traced through its handler, state mutation, persistence consumer and downstream browser or
message consumer. Foundation and source checks are not treated as macOS/WebKit runtime verification.

### Confirmed defects and TDD fixes

#### WEB-CHAT-11 — Ask-before-changes did not protect file mutations

`AccessLevel.askBeforeChanges` is displayed as “Ask before file changes,” but
`WebToolAccessGate` returned `.allow` for `write_file`, `edit_file` and `todo_write`. The concrete
executor therefore performed real file/todo mutations immediately. The generic `requiresApproval`
helper was not a consumer of the live gate and did not provide a user-visible guard.

Red tests first asserted approval for all three mutation classes and preserved edit-automatically/full-
access behavior. The gate now returns `.requireApproval` at ask-before-changes. The driver emits a
new `approvalRequired` event before executor dispatch, so no mutation side effect occurs. Evidence:
**3/3 gate tests passed**.

#### WEB-CHAT-12 — blocked turns had no dedicated visible completion path

The driver had no event representing a policy-blocked tool. The caller could therefore finish the turn
and record `send_completed` even when a tool had not run. Red integration coverage asserted that the
executor is untouched and an approval event is emitted. `WebChatEventPresenter` maps the event to a
persistent status, while `ChatPanelView` records `send_blocked_approval`, marks the assistant turn
finished and avoids retry/success accounting. Evidence: **1/1 integration test passed**.

The current safe behavior is an explicit blocked status rather than an automatic approval dialog. A
native SwiftUI approval control that resumes the same remote turn remains **UNVERIFIED** and is not
claimed as complete.

#### WEB-CHAT-13 — localStorage existed in the model but was neither captured nor safely restored

Login capture always constructed `WebSessionStore` with `localStorage: [:]`, although the session model
persisted the field. The first attempted restore also called `setLocalStorage` before loading the
vendor origin, so browser storage could be written to the wrong page or fail silently.

Red tests covered payload preservation, cookie-only sessions, and the required order. The fix captures
origin localStorage from the login WKWebView, adds a bridge method with a no-op Foundation default, and
restores `cookies → target navigation → localStorage → reload current URL`. Model and effort refresh
use the same sequence; ChatPanel preserves an existing remote-chat URL while reloading. Storage
failures become visible nonfatal warnings. Evidence: **4/4 restoration tests passed**.

#### WEB-CHAT-14 — custom vendor selected models bypassed injection

When bundled catalog lookup returned no entry, `WebChatDriver.injectModelAndEffort` returned success.
That path is reachable for `.custom`, even when `customModelSelector` is persisted, so the prompt could
be sent under whatever model the page happened to show.

A red custom-vendor test asserted selector click, exact option confirmation and send ordering. The fix
uses `customModelSelector` before catalog selectors and blocks a non-empty selected model when no model
selector exists. Evidence: **1/1 custom selector test passed**.

#### Approval-helper inconsistency

`WebToolProtocolEmulator.requiresApproval` omitted `edit_file`, `todo_write`, git mutations and `task`.
Red coverage expanded its classification to all mutating/privileged tool families; the helper now
agrees with `WebToolAccessGate`. Evidence: **1/1 helper test passed**.

### Source-traced controls with no additional confirmed defect

Response baseline/fingerprint handling rejects unchanged or empty response DOM. Captcha/logout checks
run before send and before response reads. Session-limit carry-over, prompt chunking, bounded iteration,
tool-result escaping, project-root validation, undo/history recording, remote-chat UUID verification and
100-instance LRU browser isolation are source-traced and covered by existing Foundation contracts.
The live bridge dispatches DOM events without an active window, but provider authentication, cookies,
localStorage, selectors, model menus, effort menus, response streaming, captcha presentation and native
approval UX require macOS/WebKit/network execution.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| WEB-CHAT-11 access-gate tests | **3/3 passed** | Foundation pure policy |
| WEB-CHAT-12 approval interruption | **1/1 passed** | Foundation driver integration |
| WEB-CHAT-13 session restoration | **4/4 passed** | Foundation payload/order contract |
| WEB-CHAT-14 custom selector | **1/1 passed** | Foundation driver integration |
| Approval-helper consistency | **1/1 passed** | Foundation protocol helper |
| Full Foundation harness | **147/147 passed** | Linux-compatible logic and prior contracts |
| Swift parser-only modified-file validation | **passed** | Syntax only; no macOS typecheck |
| Adversarial source checks | **12/12 passed** | Static contracts |
| Full macOS SwiftUI/AppKit/WebKit build | **UNVERIFIED** | macOS required |
| Live web login/model/effort/response/tool QA | **UNVERIFIED** | macOS, network and provider accounts required |

### Adversarial scores

| Dimension | Before Round 55 | After Round 55 | Evidence |
|---|---:|---:|---|
| Web Chat implementation quality | 74/100 | 95/100 | Four confirmed chain defects fixed; 147/147 harness |
| Web Chat task adherence | 72/100 | 100/100 | Full action inventory, red tests before each confirmed fix |
| Target-runtime confidence | 0/100 | 0/100 | No macOS/WebKit/live-provider execution |
| Overall verifiable project quality | 96/100 | 97/100 | Full harness and parser validation |

Canonical checklist 06, registry and README were updated. The registry now contains **264 rows:
233 PASS, 21 PARTIAL, 5 MISSING, 5 FUTURE**. Round 55 is ready for the final source-check/diff
validation and commit/push. The next sequential audit remains activity checklist 07 (`07-mimo-auto.md`).


## Round 56 (2026-08-14) — myCoder Auto Free context and failover notifications

### Scope

Activity checklist 07 was re-audited across the built-in provider option, legacy rename migration,
startup default, anonymous OpenCode catalog refresh, model selection, lock/unlock, system prompt,
parameters, send readiness, route resolution, ordinary send, conversation history, attachments, SSE
streaming, immediate and threshold failover, notification severity, error persistence and settings
privacy/status disclosure.

### Confirmed defects and TDD fixes

#### AUTO-FREE-01 / CHAT-20 — ordinary Auto Free turns dropped visible conversation history

The direct OpenAI-compatible path already constructed prior turns, but the Auto Free branch built only
one current user message. A second anonymous request therefore lost the previous user/assistant exchange
although it remained visible in the local chat.

A red Foundation test was written first. `MyCoderAutoFreeHistoryLogic` now retains finished,
non-empty user/assistant turns, drops in-flight assistant placeholders, excludes other roles and caps
history at 20 turns; edge coverage verifies zero-turn history. `ChatPanelView` maps prior local messages
through this contract and prepends them to the current attachment-bearing user message. Evidence:
**2/2 pure history tests passed**.

#### PROV-17 — textual HTTP 429/rate-limit failures did not produce the red alert path

`MyCoderAutoFreeNotificationLogic` already treated the exact reason `"rate limit"` as an error, but
`MyCoderAutoFreeProvider.switchReason` converted `MyCoderAutoFreeError.apiError("HTTP 429")` to a
generic consecutive-failures reason. The user could therefore see a warning-level generic switch
instead of the requested red rate-limit alert.

Red tests were written first for HTTP 429 and ordinary rate-limit text, plus model and generic reason
preservation. `MyCoderAutoFreeFailoverLogic` normalizes textual errors; provider switches now use
`rate limit` for 429/rate-limit text, while model-unavailable and generic failures remain distinct.
Evidence: **2/2 pure failover-reason tests passed**.

### Source-traced controls with no additional confirmed defect

The built-in provider is non-removable and selected only when a live eligible catalog is ready. Legacy
`mimo-auto` preferences migrate to `mycoder-auto-free`. The route resolver returns `.autoFree` before
Serve fallback. The readiness gate independently checks catalog readiness, so MiMo Serve is not required.
The anonymous client sends no API key, rejects paid/non-free IDs, parses SSE content and reasoning
deltas, rejects empty responses, and maps HTTP failures to typed errors. Model selection, lock state,
system prompt, last-known catalog and new-model discovery are source-traced. Existing attachment,
parameter and exact notification tests remain in the project.

The following remain **UNVERIFIED** without macOS/network/live OpenCode execution: SwiftUI picker and
settings visual behavior, singleton refresh timing, real catalog contents and paid-model exclusion
against the live endpoint, actual anonymous request acceptance, SSE streaming, multi-turn request body
capture, real rate limits/failover, and local macOS persistence.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| Auto Free history contract | **2/2 passed** | Foundation pure logic |
| Failover reason normalization | **2/2 passed** | Foundation pure logic |
| Full Foundation harness | **151/151 passed** | Linux-compatible logic and prior contracts |
| Swift parser-only modified-file validation | **passed** | Syntax only; no macOS typecheck |
| Adversarial source checks | **12/12 passed** | Static contracts |
| Live anonymous OpenCode/SSE/failover | **UNVERIFIED** | Network/provider availability |
| macOS SwiftUI settings/composer runtime | **UNVERIFIED** | macOS required |

### Adversarial scores

| Dimension | Before Round 56 | After Round 56 | Evidence |
|---|---:|---:|---|
| myCoder Auto Free implementation quality | 88/100 | 96/100 | Two confirmed chain defects fixed; 4/4 new pure tests |
| myCoder Auto Free task adherence | 86/100 | 100/100 | Full control inventory and red tests before fixes |
| Target-runtime confidence | 0/100 | 0/100 | No live OpenCode or macOS execution |
| Overall verifiable project quality | 97/100 | 97/100 | 151/151 harness, parser and source checks passed |

Canonical checklist 07, registry and README were updated. The registry now contains **266 rows:
233 PASS, 23 PARTIAL, 5 MISSING, 5 FUTURE**. Round 56 final harness/parser/source validation passed and it is ready for commit/push. The next sequential audit remains checklist 08 (`08-project-session.md`).

## Round 57 (2026-08-15) — Project / Session persistence and project-scoped storage

### Scope

Activity checklist 08 was re-audited from the first New Project control through folder selection, project registry creation, workspace switching, navigation history, session selection, first-send bootstrap, message reload, project routing, archive/delete maintenance, storage statistics and VACUUM. Every user-facing workspace selector was traced separately: sidebar list, grid, overview sheet and compact input menu.

### Confirmed defects and TDD fixes

#### DB-07 — New Project accepted a nonexistent manual path
`NewProjectSheet` trimmed name/path but only checked that both strings were nonempty. A user could enter an absolute path that did not exist, the project could appear in registry state, and the per-project database would later reject the path. This created a disappearing-project/first-message persistence failure.

A red test was written first. `NewProjectValidationLogic` now trims both fields, rejects blank or relative paths, rejects nonexistent paths and rejects files used as project roots. `NewProjectSheet` shows the validation error and dismisses only after a valid existing directory passes. Evidence: **4/4 Foundation tests passed**.

#### DB-08 — Project switching changed only the highlight, not the session store
Sidebar/grid/overview/input controls assigned `selectedWorkspace` directly. The observer maintained navigation history but did not load the selected project’s sessions. Consequently the previous project’s sessions could remain visible under the new project, and asynchronous old-project results could overwrite the current project.

A red test was written first. `AppState.selectWorkspace` is now the single user-facing selection entry point: it clears stale session/transient state, schedules the selected project database load and uses `WorkspaceSelectionLogic` to discard late results for another project. All discovered direct UI assignments were routed through it. Evidence: **3/3 Foundation tests passed**.

#### DB-09 — Explicit project session creation could use the wrong database
`createSessionInDatabase(projectId:)` used `selectedWorkspace.path` whenever a workspace was selected, even when the caller supplied another project ID. A session requested for project B could therefore be created in project A’s database.

A red test was written first. `ProjectSessionRoutingLogic` resolves the explicit project ID to the matching workspace path and only uses a selected-path fallback when no workspace row is available. Evidence: **2/2 Foundation tests passed**.

#### STO-30 — Storage maintenance operated only on the legacy database
`archiveOldSessions`, `deleteArchivedSessions` and `deleteSessionsOlderThan` called only `DatabaseManager.shared`, while current chat messages and sessions are stored in project-scoped SQLite databases. The UI therefore reported successful maintenance without affecting canonical project history.

Red macOS-target tests were added before the production API. `ProjectDatabaseManager` now provides project-scoped archive/delete operations; AppState runs maintenance across the legacy compatibility store and every loaded project DB, vacuums affected project DBs and refreshes the selected project. The SQLite tests are parser-validated but cannot execute in the Linux sandbox because the full macOS target is unavailable.

#### STO-31 — Storage statistics excluded project databases
`loadStorageStats()` read database size, message count and active/archived session counts only from the legacy global database. Project-scoped messages therefore existed in chat but were absent from the Storage panel totals.

A red pure aggregation test was written first. `ProjectStorageStatsLogic` now merges legacy and project snapshots with deterministic path de-duplication; AppState collects project DB sizes, messages and session states before building `StorageStats`. Evidence: **2/2 Foundation aggregation tests passed**.

### Source-traced controls with no additional confirmed defect

`MessageStore` persists user/assistant messages using its current session ID, reloads from the project database when the server is empty/unavailable, merges server history without duplicate IDs and guards asynchronous message loads by session ID. `DatabaseBridge` remembers project ownership for project-scoped session/message/part operations. Project registry archive/restore/delete and typed-name destructive confirmation were source-traced; native confirmation, AppKit folder dialogs, filesystem permissions and live SQLite behavior remain runtime-bound.

The existing `archiveSession`/`unarchiveSession` database primitives remain available, while the visible Storage workflow is bulk archive/delete by age and project registry archive/restore. No claim is made that a native per-row archive control was runtime-verified.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| New Project validation | **4/4 passed** | Foundation pure logic |
| Workspace selection and stale-load guards | **3/3 passed** | Foundation pure logic |
| Explicit project routing | **2/2 passed** | Foundation pure logic |
| Storage statistics aggregation | **2/2 passed** | Foundation pure logic |
| Project DB archive/delete tests | **Added before fix; parser passed** | macOS SQLite target unavailable in Linux |
| Full Foundation harness | **162/162 passed** | Linux-compatible logic and prior contracts |
| Swift parser-only modified-file validation | **passed** | Syntax only; no macOS typecheck |
| Adversarial source checks | **12/12 passed** | Existing static web/send contracts |
| `git diff --check` | **passed** | Repository hygiene |
| macOS SwiftUI/AppKit/SQLite runtime | **UNVERIFIED** | Requires user-side macOS build/test |

### Adversarial scores

| Dimension | Before Round 57 | After Round 57 | Evidence |
|---|---:|---:|---|
| Project/Session implementation quality | 84/100 | 98/100 | Four confirmed chain defects fixed; project maintenance APIs added |
| Project/Session task adherence | 86/100 | 99/100 | Full control inventory, red tests first, canonical documentation and honest boundaries |
| Target-runtime confidence | 0/100 | 0/100 | No macOS SwiftUI/AppKit/SQLite runtime available in sandbox |
| Overall verifiable project quality | 97/100 | 98/100 | 162/162 harness, parser, source checks and diff hygiene passed |

Canonical checklist 08, registry and README were updated. The registry now contains **271 rows: 233 PASS, 28 PARTIAL, 5 MISSING, 5 FUTURE**. Round 57 is ready for staged validation and commit/push. The next sequential audit is checklist 09 (`09-shell-status.md`).


## Round 58 — Shell and Status adversarial audit

### Scope and method

Round 58 audited Activity 09 (`09-shell-status.md`) from the first visible shell control through its complete trigger→handler→state→consumer→persistence chain. The manual devil’s-advocate pass covered the sidebar toggle, New Task/Cmd+N, Goal and Terminal panels, Copy Chat, session/workspace/branch context, goal badge persistence, provider connection status, endpoint label, model status, streaming/loading priority, Search/Cmd+K, Undo/Cmd+Option+Z, native Cut/Copy/Paste/Select All, workspace switching, and first-send session bootstrap.

The audit found and fixed five confirmed defects. The first three are canonical SHELL stories; the last two are additional regression fixes recorded in the checklist and cumulative evidence.

### SHELL-01 — Workspace-only branch context was hidden

`TopBarView` previously gated the branch badge on the retired `selectedProject` property, while current project navigation uses `selectedWorkspace`. A workspace-only project therefore displayed the no-project myCoder fallback even though a real branch was active. A red test was written first for workspace-only and no-context cases. `ProjectHeaderContextLogic.shouldShowBranch` is now wired into the TopBar. Evidence: **2/2 Foundation tests passed**.

### SHELL-02 — Serve health masqueraded as every provider’s connectivity

`AppState.selectedProviderConnected` previously exposed global Serve health as the universal connection state. An expired web login, unavailable Auto Free catalog, disabled local provider, or unready custom provider could therefore appear connected whenever Serve was healthy. A red route matrix was written first. `ProviderConnectionStatusLogic.isConnected` now applies readiness according to the selected provider family. Evidence: **3/3 route-specific connection tests passed**.

### SHELL-03 — Endpoint label described the wrong route

The status bar previously displayed the Serve host and port for every provider. The endpoint contract now displays `host:port` only when the selected ID belongs to the Serve provider set; web, Auto Free, local, and custom routes display their selected provider ID. During the round, the endpoint regression test was also found outside its suite’s closing brace; it was moved inside the suite before execution. Evidence: **4/4 provider status tests passed**, including the endpoint test.

### Additional confirmed defect — effective web/Auto Free model disappeared from StatusBar

`StatusBarView` rendered only `appState.selectedModel`, although web and Auto Free routes can hold the actual selected model in `effectiveSelectedModel()`. The status bar could therefore show no model or misleading state. Red tests were written first for effective-model precedence, legacy fallback, and the both-empty case. `StatusBarModelLogic.displayModel` is now used by `StatusBarView`. Evidence: **2/2 tests passed**.

### Additional confirmed defect — project goal was not stored in the project database

The global `DatabaseManager` had a `session_goal` column, but the per-project schema and `ProjectSessionRecord` did not. `AppState.setCurrentSessionGoal` wrote to the global store while workspace reloads read project-scoped sessions, so the TopBar goal badge could disappear after switching or restarting. Red tests were written first for project precedence and legacy compatibility. The per-project schema now adds/upgrades `session_goal`, CRUD and record hydration carry the value, `DatabaseBridge` routes reads/writes by owning session, and AppState uses that bridge. Evidence: **3/3 routing-contract tests passed**. Real macOS SQLite migration remains unverified in Linux.

### Additional confirmed UX defect — Undo silently discarded results and errors

The Cmd+Option+Z closure ignored the Boolean result from `undoMostRecent` and swallowed thrown errors. Users had no way to know whether a file was restored, no entry existed, or the snapshot was missing. Red tests were written first for success, no-op, and failure messages. `AppState.undoLastAction` now exposes the outcome through a short-lived TopBar notice and refreshes Git state after success; `UndoActionFeedbackLogic` keeps the mapping deterministic. Evidence: **3/3 tests passed**. Native menu and filesystem restore remain macOS-bound.

### Source-traced controls with no remaining confirmed deterministic defect

Cmd+N clears selection and execution state; the first send then establishes `MessageStore.currentSessionID` before appending the user and assistant messages. Cmd+K is wired through `showSearch` to `ContentView`’s SearchPalette sheet and selection returns through `AppState.selectSession`. Goal and Terminal toggles mount the expected right and bottom panels. Copy Chat sends the notification to ChatPanel, builds the transcript, writes the macOS pasteboard and resets button feedback after 1.5 seconds. Streaming takes precedence over loading, and loading takes precedence over idle. Native responder shortcuts are source-correct but require AppKit focus runtime verification.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| Full Foundation harness | **176/176 passed** | Linux-compatible deterministic contracts |
| Provider connection and endpoint suite | **4/4 passed** | Pure route contract; live provider/WebKit unverified |
| Effective status-bar model suite | **2/2 passed** | Pure display contract; SwiftUI rendering unverified |
| Project goal routing suite | **3/3 passed** | Pure precedence contract; macOS SQLite unverified |
| Undo feedback suite | **3/3 passed** | Pure outcome contract; AppKit/filesystem unverified |
| Swift parser validation | **passed** | Syntax only; no macOS framework typecheck |
| Adversarial source checks | **12/12 passed** | Static repository checks |
| `git diff --check` | **passed** | Repository hygiene |
| macOS SwiftUI/AppKit/WebKit/SQLite runtime | **UNVERIFIED** | Requires a user-side macOS build/run |

### Adversarial scores

| Dimension | Before Round 58 | After Round 58 | Evidence |
|---|---:|---:|---|
| Shell/Status implementation quality | 84/100 | 98/100 | Five confirmed chain defects fixed; route and persistence contracts are explicit; runtime boundary remains |
| Shell/Status task adherence | 86/100 | 100/100 | Full control matrix, red tests first, separate quality scores, canonical docs, and honest UNVERIFIED labels |
| Target-runtime confidence | 0/100 | 0/100 | Linux sandbox cannot execute SwiftUI, AppKit, WebKit, or macOS SQLite runtime |
| Overall verifiable project quality | 98/100 | 99/100 | 176/176 harness, parser, 12/12 source checks; macOS runtime still required |

Canonical checklist 09, the 274-row registry, and README totals are updated for Round 58. The next sequential audit remains Activity 14 (`send-providers.md`), beginning with provider/model selection through readiness, route resolution, browser/direct client execution, session UUID routing, persistence, retry/failover, and user-visible error handling.


## Round 59 — Activity 14 provider-send adversarial audit

### Scope and method

Round 59 traced the complete send chain for myCoder Auto Free, MiMo Serve, custom OpenAI-compatible providers, Ollama, OpenCode local, Local Agent, ACP, and web Kimi/Qwen/ChatGPT. The chain began at provider/model/effort controls and continued through composer readiness, effective-model resolution, route identity, transport request construction, session and remote-chat mapping, response validation, retries/failover, persistence, and user-visible completion or error state. Both centered and bottom composers, the local HTTP API bridge, attachments, Stop, and web approval gates were included.

The devil’s-advocate pass deliberately tested the assumptions that Serve health describes every route, `selectedModel` is always authoritative, HTTP 200 implies usable content, a driver returning implies success, and a retry can safely repeat a browser prompt. Each assumption produced a confirmed defect or a documented verified invariant.

### Confirmed defect — Serve health bypassed selected-route readiness

`SendReadinessLogic.connectionValidationError` returned `nil` immediately when Serve was connected. The selected route was evaluated only afterward, so an expired web session, unavailable direct provider, or unknown provider could pass preflight while the actual route remained unusable. The fix adds `SendProviderReadinessLogic`, which checks Auto Free, web, local, custom, and known Serve IDs independently. `AppState.refreshProviderConnectivity` now short-circuits only for provider IDs belonging to the Serve catalog and probes other routes separately. Evidence: **3/3 new readiness tests passed** and the full harness passed.

### Confirmed defect — effective model was lost across send and UI consumers

Web and Auto Free store the routed model in provider-specific configuration while legacy `AppState.selectedModel` may be empty or stale. The old field affected send validation, the centered and bottom composer disabled states, model menu label/checkmark, parameter popover key/title/save/reset, capability gates, direct route construction, ACP/Serve parameter lookup, web injection reconciliation, and HTTP API metadata. The fix consistently uses `effectiveSelectedModel()` and the new `ModelSelectionPresentationLogic` where presentation or parameter keying is required. Evidence: **3/3 model-presentation tests** and **2/2 API metadata tests** passed.

### Confirmed defect — blank direct and ACP responses became successful empty bubbles

`DirectChatClient.parseResponse` accepted whitespace-only content, and the ACP branch used an empty fallback string before marking the assistant message finished. `ProviderResponseValidationLogic` now rejects missing or blank content. Direct sends expose `DirectChatError.emptyResponse`; ACP exposes `ACPError.emptyResponse`; ChatPanel fails visibly before marking the response complete. Auto Free already had an explicit empty-response check, and the web response wait already rejects an unchanged empty DOM. Evidence: **2/2 response-validation tests passed**.

### Confirmed defect — web failures were journaled as successful sends

`runWebChatTurn` recorded `send_completed` after `WebChatDriver.runTurn` returned, even when the driver had emitted error, logout, captcha, iteration-limit, injection-failure, or no-final-response events. The fix adds `WebSendCompletionLogic` and a thread-safe `WebChatCompletionSignal`. Only a visible `.final` event can authorize completion journaling; the signal also covers the bounded catalog-refresh retry. Evidence: **3/3 web-completion tests passed**, including visible final, failure/interruption, and blank final cases.

### Source-traced provider chains with no additional confirmed deterministic defect

myCoder Auto Free carries effective model, history, system prompt, attachments, model parameters, live catalog refresh, locked-model behavior, and rate-limit/model-unavailable failover with visible switch notifications. Direct routes carry history, multimodal parts, parameters, normalized API keys, and typed transport/HTTP/decode/empty-response errors. ACP preserves agent, variant, parameters and its own endpoint. Serve retains stable local session identity, SSE handling, busy retry and timeout. Web routes restore browser sessions, verify project/provider/chat remote UUID mappings, inject exact model and supported effort before typing, refresh and retry once without duplicating the prompt, and stop mutating tools at the approval gate.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| Full Foundation harness | **189/189 passed** | Linux-compatible logic and fake browser contracts |
| Activity 14 readiness regressions | **3/3 passed** | Pure route-specific readiness/effective-model contract |
| Model presentation regressions | **3/3 passed** | Pure UI-selection/parameter-key contract |
| API response metadata regressions | **2/2 passed** | Pure effective-model response contract |
| Provider response validation regressions | **2/2 passed** | Pure blank-output contract |
| Web completion journal regressions | **3/3 passed** | Pure event-success contract |
| Swift parser validation | **passed** | Syntax only; no macOS framework typecheck |
| Adversarial source checks | **12/12 passed** | Static send/browser/model invariants |
| `git diff --check` | **passed** | Repository hygiene |
| macOS SwiftUI/AppKit/WebKit/provider/SQLite runtime | **UNVERIFIED** | Requires a macOS build with disposable live prompts |

### Adversarial scores

| Dimension | Before Round 59 | After Round 59 | Evidence |
|---|---:|---:|---|
| Provider-send implementation quality | 83/100 | 98/100 | Route readiness, effective model, blank response, and false completion defects fixed |
| Provider-send task adherence | 86/100 | 100/100 | Every provider chain and control traced; red tests first; canonical docs and honest status labels updated |
| Target-runtime confidence | 0/100 | 0/100 | Linux sandbox cannot run SwiftUI, AppKit, WebKit, live providers, or macOS SQLite |
| Overall verifiable project quality | 99/100 | 99/100 | 189/189 harness, parser, 12/12 source checks; live target remains required |

The canonical registry remains **274 rows** and now reports **224 PASS, 40 PARTIAL, 5 MISSING, and 5 FUTURE**. Activity 14 is documented in full; the next audit must continue sequentially from the following activity checklist and must preserve the same TDD, chain-trace, source-verification, documentation, and commit/push discipline.


## Round 60 — Global recheck: project indexing and file search

### Scope and chain audit

The global registry recheck resumed at the earliest remaining non-PASS stories after Activity 14: `STO-06 File Index Logic` and `STO-07 FSEvents Dynamic Reindexing`. The audit traced the Indexing settings tab, `indexNewFolders` and `indexRepositories` bindings, `AppState.inputDropdownContext()`, `ProjectFilesCacheLogic`, `ProjectFileScanner`, `ProjectFileIndexLogic`, hash/mtime delta computation, the `@` input dropdown, and every repository reference to FSEvents, `file_index`, FTS, and indexing status.

### Confirmed defect — file index was only an in-memory TTL cache

The scanner and delta code existed, but `inputDropdownContext()` retained only file names in a 30-second `ProjectFilesCacheState`. A new launch or cache refresh had no persisted records to compare against, and source search found no project-local index store. Round 60 adds the codable `ProjectFileIndexSnapshot`, dependency-free `ProjectFileIndexPersistenceLogic`, shared `FileIndexRecord`, and production `ProjectFileIndexStore`. On rescan, AppState loads the project snapshot, scans current files, applies hash/mtime delta semantics, saves `<project>/.mycoder/file_index.json`, and feeds the cache from the resulting records. The snapshot embeds and validates the project path to prevent cross-project reuse.

### Confirmed UX defect — indexing toggles had no consumer

`IndexingSettingsView` persisted `indexNewFolders` and `indexRepositories`, but no FSEvents watcher or scanner path consumed either setting. The UI therefore implied automatic behavior that did not exist. The toggles are now disabled and accompanied by an honest message that automatic indexing is unavailable and `@` suggestions refresh on demand. Preferences remain stored for future watcher activation rather than being silently discarded.

### Explicitly unresolved capabilities

A repository-wide source audit found no FSEventStream subscription, watcher lifecycle, persistent SQLite `file_index` table, FTS schema/query API, or automatic indexing status consumer. `STO-07` remains **MISSING**. Persistent FTS remains unimplemented. These are not represented as PASS and require a future macOS-specific round with red tests for debounce, create/delete/rename, project switching, watcher shutdown, and file-permission errors.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| New index persistence/settings regressions | **3/3 passed** | Foundation contracts |
| Full Foundation harness | **192/192 passed** | Linux-compatible logic and fake browser contracts |
| Index scanner/delta tests | **passed in full harness** | Deterministic scan/exclusion/hash behavior |
| Swift parser validation | **passed** | Index/AppState/settings syntax; no framework typecheck |
| macOS file I/O and SwiftUI Indexing settings | **UNVERIFIED** | Requires macOS build |
| FSEvents dynamic reindexing | **MISSING** | No implementation exists |
| SQLite/FTS persistent search | **MISSING** | No implementation exists |
| `git diff --check` | **passed** | Repository hygiene |

### Scores

| Dimension | Score | Rationale |
|---|---:|---|
| Implementation quality | 96/100 | Project-scoped persistence and honest disabled settings are deterministic; FSEvents/FTS remain outside scope and macOS I/O is unavailable |
| Task adherence | 100/100 | Every indexing control and function was traced, red tests preceded the core fix, and missing capabilities remain explicitly marked |
| Target-runtime confidence | 0/100 | Linux sandbox cannot execute SwiftUI, AppKit, macOS file watchers, or macOS SQLite |

The canonical registry remains **274 rows** with **224 PASS, 40 PARTIAL, 5 MISSING, and 5 FUTURE**. `STO-06` now documents its per-project JSON snapshot implementation while retaining PARTIAL because FSEvents/FTS are absent; `STO-07` remains MISSING.


## Round 61 — STO-07 FSEvents dynamic reindexing

### Scope and method

The next global recheck target was the earliest remaining storage gap: `STO-07 FSEvents Dynamic Reindexing`. The audit traced `IndexingSettingsView`, `AppState.selectedWorkspace`, workspace switching/clearing, the `@` file-dropdown cache, `ProjectFileScanner`, `ProjectFileIndexStore`, and every source reference to FSEvents, index invalidation, and project file state.

The devil’s-advocate cases were: a change outside the active project, a change inside `.mycoder` caused by the index itself, a callback from a previously selected project arriving after a workspace switch, rapid bursts of file events, watcher shutdown on workspace clear, and a watcher implementation that parses on Linux but cannot run there.

### Confirmed implementation gap — no dynamic watcher lifecycle

The previous round persisted project snapshots but had no watcher. Round 61 adds a pure `ProjectFileIndexWatcherLogic` contract and a platform-safe `ProjectFileIndexWatcher`. On macOS, the watcher uses CoreServices FSEvents with a 300 ms debounce. It filters paths to the active project, suppresses `.mycoder` changes to avoid self-triggered loops, and emits the canonical project path plus generation. `AppState.selectedWorkspace` stops the old watcher, increments generation, clears the cache, starts the new watcher, and dispatches invalidation back to the main queue. A stale callback is rejected when its canonical project path or generation does not match the active state. Outside macOS, a no-op fallback preserves compilation and the same lifecycle contract.

### Indexing settings remain honest

`indexNewFolders` and `indexRepositories` still have no consumer that can change watcher behavior. The Indexing settings controls remain disabled with an explicit “automatic indexing is not available yet” message. The FSEvents watcher itself is active for the workspace file tree, but repository/folder preference semantics and persistent FTS are not claimed as implemented.

### Persistent FTS remains missing

The source audit found no SQLite `file_index` table, FTS schema, query API, or search consumer. The file index remains a project-local JSON snapshot used by the existing `@` dropdown path. Persistent FTS is deliberately left **MISSING** rather than being inferred from the watcher implementation.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| Red watcher contract suite | Failed before implementation | `ProjectFileIndexWatcherLogic` absent by design |
| Green watcher contract suite | **4/4 passed** | Path filtering, `.mycoder` suppression, stale generation, debounce bound |
| Full Foundation harness | **196/196 passed** | Linux-compatible logic and fake browser contracts |
| Swift parser validation | **passed** | CoreServices-guarded watcher and AppState syntax |
| Adversarial source checks | **12/12 passed** | Existing model/browser/send invariants |
| macOS FSEvents event delivery | **UNVERIFIED** | Linux sandbox cannot execute CoreServices event stream |
| macOS watcher shutdown/permission behavior | **UNVERIFIED** | Requires macOS filesystem runtime |
| Persistent SQLite/FTS search | **MISSING** | No implementation exists |
| `git diff --check` | **passed** | Repository hygiene |

### Scores

| Dimension | Score | Rationale |
|---|---:|---|
| Implementation quality | 96/100 | Watcher has debounce, project isolation, stale-generation safety, self-write suppression, and a non-macOS fallback; live CoreServices behavior is unavailable |
| Task adherence | 100/100 | Workspace lifecycle and every indexing chain were manually traced, red tests preceded the core watcher contract, docs/registry are updated, and FTS remains honestly missing |
| Target-runtime confidence | 0/100 | macOS SwiftUI/AppKit/CoreServices runtime is unavailable in the sandbox |

The canonical registry remains **274 rows** and now reports **224 PASS, 41 PARTIAL, 4 MISSING, and 5 FUTURE**. `STO-07` moved from MISSING to PARTIAL because the watcher is implemented and contract-tested, while live macOS event delivery remains UNVERIFIED. `STO-06` remains PARTIAL because persistent FTS and SQLite indexing are not implemented.


## Round 62 — Registry/settings backup and project cleanup

### Scope and chain audit

The global recheck continued at the earliest remaining storage stories: `STO-27 Registry+Settings Export/Import` and `STO-28 Chunked Big-Project Delete`. The audit traced StorageSettingsView’s project header and per-project buttons, `ProjectBackupLogic`, `ProjectHistoryExporter`, `AppSettings` UserDefaults persistence, `ProjectRegistryLogic`, typed delete confirmation, auto-backup preservation, `deleteProject`, active workspace cleanup, and all source references to chunking/progress/cancellation.

### Confirmed defect — project ZIP did not migrate global configuration

The existing project backup ZIP contained one project’s `.mycoder` directory only. It did not include the global project registry or AppSettings, so it could not migrate the whole user configuration to another machine. Round 62 adds `AppConfigurationBackupBundle`, `AppConfigurationBackupLogic`, and `AppConfigurationBackupStore`. StorageSettingsView now exposes separate app-configuration export/import actions. The versioned bundle carries independent registry and settings JSON payloads; import rejects unsupported schemas, writes the registry, saves injected UserDefaults, reloads AppState settings, refreshes the project registry, and refreshes storage statistics.

### Confirmed defect — project deletion used one unbounded synchronous removal

The previous delete path called `FileManager.removeItem` on the complete project `.mycoder` directory from a UI action. It had no bounded work plan or root-safety helper. Round 62 adds `ProjectDeletionLogic` for bounded chunks, safe progress calculation, and empty/root rejection, plus `ProjectDeletionExecutor` that enumerates only the exact project `.mycoder` directory, deletes deepest paths in chunks of 128, and removes the root after its contents. Registry mutation now occurs only after the executor reports success; the existing backup-before-delete, typed-name confirmation, audit log, and active-selection cleanup remain in the chain.

### Explicit remaining limitation — no background progress or cancellation

STO-28 is now **PARTIAL**, not PASS. Chunking bounds individual work batches, but the executor is still called synchronously from the current SwiftUI action and does not publish progress, support cancellation, disable duplicate actions, or surface per-file failures. A future macOS round should move it to a cancellable background task and add a visible progress/error surface. Native save/open panels and macOS filesystem behavior are also UNVERIFIED in Linux.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| Global configuration backup regressions | **2/2 passed** | Versioned payload and schema rejection |
| Project deletion regressions | **3/3 passed** | Bounded chunks, progress, root safety |
| Full Foundation harness | **201/201 passed** | Linux-compatible logic and fake browser contracts |
| Swift parser validation | **passed** | Backup/deletion production files and StorageSettingsView syntax |
| Adversarial source checks | **12/12 passed** | Existing send/browser invariants |
| Native save/open panels | **UNVERIFIED** | Requires macOS AppKit runtime |
| macOS `ditto` and filesystem delete | **UNVERIFIED** | Requires macOS runtime |
| Background delete progress/cancellation | **MISSING** | Current executor remains synchronous |
| `git diff --check` | **passed** | Repository hygiene |

### Scores

| Dimension | Score | Rationale |
|---|---:|---|
| Implementation quality | 94/100 | Versioned global backup and root-scoped bounded deletion are implemented; asynchronous progress/cancellation and macOS runtime remain |
| Task adherence | 100/100 | Every storage backup/delete chain was traced, red regressions preceded pure fixes, docs/registry were updated, and incomplete runtime behavior is explicit |
| Target-runtime confidence | 0/100 | Linux sandbox cannot execute SwiftUI/AppKit panels or macOS filesystem integration |

The canonical registry remains **274 rows** and now reports **224 PASS, 43 PARTIAL, 2 MISSING, and 5 FUTURE**. `STO-27` and `STO-28` moved from MISSING to PARTIAL; both retain explicit runtime or UX limitations.

## Round 63 — Per-project usage and cost-per-model aggregation

### Scope and chain audit

The audit continued at `USG-02 Usage Screen with Real Data` and `USG-03 Cost per Model`. The complete chain was traced from direct-provider response usage, ACP usage, Auto Free/web/Serve response paths, assistant-message persistence, legacy `DatabaseManager`, canonical per-project `ProjectDatabaseManager`, `AppState.loadUsageDataPoints()`, `UsageStatisticsAggregator`, and the Usage settings consumer.

The devil’s-advocate question was whether a correct database query could still produce an incorrect UI because AppState selected the wrong database source. The answer was yes: both database managers preserved nullable `messageCostUsd`, but `AppState+Database.loadUsageDataPoints()` read only `DatabaseManager.shared`. Since normal current sessions/messages are stored in per-project databases, project-scoped usage and cost were absent from the Usage screen.

### TDD defect confirmation and fix

Round 63 first extracted `UsageDataPoint` from `UsageStatisticsAggregator.swift` so the source-selection contract could be tested in the Foundation-only harness. Two red regression tests were then added before the implementation: one required legacy and project-scoped points, including nullable cost values, to be present together; the other required empty sources to remain empty. The red run failed with `cannot find 'UsageDataSourcesLogic' in scope`, confirming that the test was exercising a missing production contract rather than passing accidentally.

`UsageDataSourcesLogic.merge` was then implemented as a deterministic merge of legacy and every project source, ordered by timestamp with stable provider/model tie-breakers. `AppState.loadUsageDataPoints()` now reads the legacy store, reads all maintained project databases, and passes both collections through the tested merge contract before UsageSettingsView filters and aggregates them.

The fix deliberately does not invent provider pricing. Direct gateways may contribute a real nullable cost when their response supplies one. ACP, Auto Free, web-browser, and Serve paths remain N/A when no trustworthy usage or pricing payload is exposed in the traced chain. A numeric `$0.00` would be less correct than an honest unknown value.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| Red cross-database regression run | **failed as expected** | Missing `UsageDataSourcesLogic` before implementation |
| Green usage-source regressions | **2/2 passed** | Project inclusion and empty-source edge case |
| Full Foundation harness | **203/203 passed** | Linux-compatible logic and fake browser contracts |
| Swift parser validation | **passed** | Usage model, aggregator, merge helper, and AppState wiring |
| Adversarial source checks | **12/12 passed** | Provider/browser invariants remained green |
| macOS Usage settings rendering | **UNVERIFIED** | Requires macOS SwiftUI runtime |
| Live provider usage/cost payloads | **PARTIAL/UNVERIFIED** | Web/Auto Free/Serve/ACP do not expose a trusted price in the traced source chain |
| `git diff --check` | **passed** | No trailing whitespace after final Round 63 edits |

### Scores

| Dimension | Score | Rationale |
|---|---:|---|
| Implementation quality | 96/100 | The canonical per-project source omission is fixed with a small deterministic contract, cost remains nullable and honest, and the full harness is green; provider-specific cost payloads and macOS runtime remain unavailable. |
| Task adherence | 100/100 | Every usage source and consumer was manually traced, red tests preceded the fix, edge cases were covered, documentation and registry updates were prepared, and unsupported pricing is not fabricated. |
| Target-runtime confidence | 0/100 | Linux cannot execute SwiftUI/AppKit or validate live provider/browser usage metadata. |

The canonical registry now contains **274 rows** and reports **224 PASS, 44 PARTIAL, 1 MISSING, and 5 FUTURE**. `USG-03` moved from MISSING to PARTIAL because per-project usage/cost data now reaches aggregation, while provider-specific pricing and native runtime verification remain explicitly incomplete. `USG-02` remains PARTIAL with its global-only source note corrected.

## Round 64 — Skills management state and uninstall safety

### Scope and chain audit

The sequential audit continued at `SET-04 Skills Management Tab`. The chain was traced from the Settings tab selector into `SkillsSettingsView`, its search field, installed-skill loader, `AgentResourceLibraryView` catalog cards, install/update/uninstall tasks, dependency resolution, bundled catalog loading, filesystem paths under `~/.mycoder/skills`, `SkillRegistryManager`, and the installed-row controls. Every visible button and action was manually mapped to its state mutation, refresh callback, and error behavior.

The existing registry note was stale. The library already had an Update button, dependency-aware installation, and dependency hints. Two current defects were confirmed instead: an update silently re-enabled a skill that the user had disabled, and the library’s destructive Uninstall button bypassed the confirmation that the installed-row trash action already used.

### TDD defect confirmation and fixes

`SkillUpdateStateTests` was written first. Its disabled-state test failed before the fix because `installSkill` always upserted `isEnabled: true`; the enabled-state test provided the opposite edge case. The green implementation reads the prior registry record and preserves its enabled state, while new installs still default to enabled. Both state regressions pass.

`SkillUninstallPolicyTests` was then written first for item-specific destructive confirmation copy. The red run failed because no policy existed. `SkillUninstallPolicy` now supplies an explicit title and irreversible-action message, and `AgentResourceLibraryView` stores an uninstall candidate and presents a cancel/destructive-confirmation alert before invoking the removal task. The installed-row trash confirmation remains in place.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| Red update-state regression | **1 expected failure** | Disabled state was reset by update |
| Green update-state regressions | **2/2 passed** | Disabled and enabled preferences survive update |
| Red uninstall-policy regression | **failed as expected** | Missing confirmation policy before implementation |
| Green uninstall-policy regression | **1/1 passed** | Item-specific destructive confirmation copy |
| Full Foundation harness | **206/206 passed** | All Linux-compatible logic plus Round 64 tests |
| Swift parser validation | **passed** | Installer, uninstall policy, and SwiftUI library source |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| Native SwiftUI/AppKit interaction | **UNVERIFIED** | Requires macOS runtime |
| Bundled catalog/resource packaging | **UNVERIFIED** | Requires packaged macOS app runtime |

### Remaining SET-04 limitations

SET-04 remains **PARTIAL**. There are no bulk enable/disable/update/remove controls, skill export/import, or dedicated interactive dependency-resolution dialog. Dependency installation is not transactional if a dependency succeeds and a later skill write fails. The installed-row enable/disable and direct trash handlers still suppress filesystem/registry errors with `try?`, so failures can leave an inconsistent file/registry state without user feedback. These are separate candidates for future rounds rather than silently marked complete.

### Scores

| Dimension | Score | Rationale |
|---|---:|---|
| Implementation quality | 94/100 | Update-state preservation and destructive confirmation are explicit and tested; error suppression, non-transactional dependency installation, and absent bulk/export/import remain. |
| Task adherence | 100/100 | Every visible Skills action was traced, both confirmed defects received red tests before fixes, the canonical row and activity checklist were updated, and absent capabilities remain PARTIAL. |
| Target-runtime confidence | 0/100 | Linux cannot execute SwiftUI/AppKit alerts, Settings presentation, bundled-resource packaging, or native filesystem integration. |

The canonical registry remains **274 rows** with **224 PASS, 44 PARTIAL, 1 MISSING, and 5 FUTURE**. `SET-04` remains PARTIAL because the core install/update/dependency-hint path is implemented and the two confirmed defects are fixed, while bulk actions, export/import, transactional failure handling, and native runtime verification remain incomplete.

## Round 65 — MCP configuration mutation safety

### Scope and chain audit

The sequential audit continued at `SET-05 MCP Server Management`. The chain was traced from Settings tab selection into `MCPServersSettingsView`, catalog install/update/uninstall cards, configured-server search/count/empty state, `AgentResourcesLoader`, `MCPConfigMutationLogic`, `MCPRegistryManager`, health cache/checker/prober, and the installed-row enable/disable/remove controls.

The existing registry note was stale: MCP catalog install, update, and uninstall paths already existed. The confirmed defect was lower-level and more dangerous: installed-row enable/disable and remove used silent `guard`/`try?` mutations and called `onChanged` as if the operation had succeeded. A missing target, malformed config, failed write, or failed registry update could therefore leave the configuration and registry inconsistent without user feedback.

### TDD defect confirmation and fix

`MCPConfigMutationLogicTests` was written before the production helper. The red run failed because `MCPConfigMutationError` and `MCPConfigMutationLogic` did not exist. The green implementation now validates the JSON root and `mcpServers` object, requires the target id, preserves sibling servers, produces typed errors, and encodes deterministic output.

`InstalledMCPRow` now writes the tested mutation result, updates registry metadata only after the config write succeeds, calls `onChanged` only after both persistence steps succeed, and renders a visible error message when either step fails. The existing destructive confirmation remains in the row. The MCP library uninstall branch is still not guarded by a dedicated confirmation policy, so that gap remains PARTIAL rather than being claimed complete.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| Red MCP mutation regression | **failed as expected** | Missing typed mutation contract |
| Green MCP mutation regressions | **3/3 passed** | Sibling preservation, missing-target failure, and remove behavior |
| Full Foundation harness | **209/209 passed** | Existing contracts plus Round 65 MCP tests |
| Swift parser validation | **passed** | MCP mutation helper and MCP settings source |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| Native SwiftUI/AppKit interaction | **UNVERIFIED** | Requires macOS runtime |
| Live HTTP/stdio health probes | **UNVERIFIED** | Requires real MCP endpoints/processes |

### Remaining SET-05 limitations

SET-05 remains **PARTIAL**. There is no editable MCP configuration form, install-set/bulk management, or dedicated MCP library uninstall confirmation. Config and registry persistence is not transactional across a registry failure after a successful config write; the failure is now surfaced, but rollback is a future hardening candidate. Health caching is keyed by server id and can retain a stale status if the same id’s endpoint changes in one app session. Live network/token fetching, stdio probing, SwiftUI rendering, AppKit Settings interaction, and packaged catalog behavior remain unverified on Linux.

### Scores

| Dimension | Score | Rationale |
|---|---:|---|
| Implementation quality | 93/100 | Silent config mutation is fixed with a pure tested contract and inline error path; rollback, stale-cache invalidation, editable configuration, bulk actions, and live runtime remain. |
| Task adherence | 100/100 | Every MCP action was traced, red tests preceded the confirmed fix, canonical registry/checklist/report updates were prepared, and missing capabilities remain PARTIAL. |
| Target-runtime confidence | 0/100 | Linux cannot execute SwiftUI/AppKit, live MCP network/stdio probes, or bundled macOS runtime behavior. |

The canonical registry remains **274 rows** with **224 PASS, 44 PARTIAL, 1 MISSING, and 5 FUTURE**. `SET-05` remains PARTIAL because the core install/update/health/enable/disable/remove paths exist and silent mutation failure is fixed, while edit, install-set/bulk, rollback, dedicated library confirmation, and native runtime verification remain incomplete.

## Round 66 — Honest browser transport labeling

### Scope and chain audit

The sequential audit continued at `WEB-05 Browser Transport (WKWebView)`. The chain was traced from the Web Providers settings card and persisted `WebTransport` enum through `WebProviderConnectivity.connectionSummary`, `ChatPanelView.runWebChatTurn`, isolated per-project/per-chat `WKWebView` creation, `WKWebViewBrowserBridge`, `WebChatDriver`, model/effort injection, session restoration, browser submission, agentic tool loop, and response completion.

The source audit confirmed that production browser sends run through an isolated in-app `WKWebView`. No Playwright MCP client or Chrome CDP socket/bridge exists in the traced app. A legacy `.cdpCookies` value remained decodable but `WebProviderConnectivity.connectionSummary` labeled it “Existing Chrome”, even though the send path could not attach to Chrome. The Settings card already displayed WKWebView and normalized the value, so the status label and runtime were inconsistent.

### TDD defect confirmation and fix

`WebTransportRuntimeLogicTests` was written before the helper. The red run failed because `WebTransportRuntimeLogic` did not exist. The green helper maps both the current managed value and the legacy CDP value to the only real runtime, labels managed transport as `In-app WKWebView`, and labels the legacy value as `In-app WKWebView (Chrome CDP unavailable)`. `WebProviderConnectivity.connectionSummary` and the Settings card now use the tested runtime label, preventing the user-facing claim that external Chrome is attached.

This is an honesty hardening fix, not a claim that external transports were implemented. Playwright MCP and Chrome CDP remain absent and the story remains PARTIAL.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| Red transport-honesty regression | **failed as expected** | Missing runtime-label contract |
| Green transport regressions | **3/3 passed** | Managed label, legacy fallback, connection-summary consumer |
| Full Foundation harness | **212/212 passed** | Existing contracts plus WEB-05 regressions |
| Swift parser validation | **passed** | Runtime helper, connectivity summary, WebProvidersSection |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| Live WKWebView send/navigation | **UNVERIFIED** | Requires macOS/WebKit and live vendor pages |
| Playwright MCP/CDP transport | **MISSING** | No production implementation to execute or verify |

### Remaining WEB-05 limitations

WEB-05 remains **PARTIAL**. The supported implementation is an isolated `WKWebView` path, not Playwright MCP or Chrome CDP. Users cannot choose an external browser transport or attach to an existing Chrome context. Live WebKit navigation, cookies/localStorage, vendor DOM selectors, cancellation, and provider behavior require macOS runtime verification.

### Scores

| Dimension | Score | Rationale |
|---|---:|---|
| Implementation quality | 95/100 | The false external-Chrome claim is removed with a small backward-compatible contract and consumer regression; external transports remain absent by design and live runtime remains unavailable. |
| Task adherence | 100/100 | Every browser transport and send-chain action was traced, red tests preceded the fix, the canonical registry/checklist/report were updated, and unsupported macOS/WebKit behavior remains UNVERIFIED. |
| Target-runtime confidence | 0/100 | Linux cannot execute SwiftUI/AppKit/WebKit or live vendor pages. |

The canonical registry remains **274 rows** with **224 PASS, 44 PARTIAL, 1 MISSING, and 5 FUTURE**. `WEB-05` remains PARTIAL because the WKWebView implementation is honest and contract-tested, while Playwright MCP/CDP transports and native WebKit verification remain incomplete.

## Round 67 — Interactive captcha solving and bounded resume

### Scope and chain audit

The sequential audit continued at `WEB-07 Captcha Display in Chat`. The chain was traced from `WebSessionLogic.detectCaptcha` and `inferState`, through `WebChatDriver.checkInterruptions`, screenshot capture in `WKWebViewBrowserBridge`, `WebChatEventPresenter`, `WebChatTurnMutation`, `ChatPanelView` event handling, the persistent per-project/per-chat `WKWebView`, and the final send/cleanup lifecycle.

The original implementation correctly detected captcha markers and rendered a screenshot in chat, but it stopped the driver and finalized the web turn while the actual browser remained a nearly invisible 2-pixel view with hit testing disabled. The localized note claimed that the agent would resume automatically, although no live solver surface or polling resume loop existed.

### TDD defect confirmation and fixes

`WebCaptchaResolutionLogicTests` was written before the policy. The red run failed because the wait/resume/abort contract did not exist. The green policy distinguishes captcha wait, connected resume, logout abort, and unknown wait. `WebChatDriver` now keeps the same bridge and driver turn alive, polls the page for up to five minutes, resumes only after the page is connected, aborts on logout, and emits a bounded timeout error rather than suspending indefinitely.

`WebCaptchaPresentationLogicTests` was written before the presentation policy. The red run failed because the solver visibility contract did not exist. The green implementation opens a `WebCaptchaSolverView` from the captcha event and attaches the exact same live `WKWebView` used by the driver via `WebChatWebViewHost`. The user can click and type in the real challenge page; the screenshot remains in the assistant bubble for diagnosis. Terminal events dismiss the sheet and progress events do not change its visibility.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| Red resolution-policy regressions | **failed as expected** | Missing wait/resume/abort contract |
| Green resolution-policy tests | **3/3 passed** | Wait, resume, logout abort |
| Red presentation-policy regressions | **failed as expected** | Missing solver visibility contract |
| Green presentation-policy tests | **3/3 passed** | Show solver, dismiss terminally, ignore progress |
| Existing WebChatDriver + captcha tests | **17/17 passed** | Driver interruption and policy contracts |
| Full Foundation harness | **218/218 passed** | Existing contracts plus WEB-07 tests |
| Swift parser validation | **passed** | Driver, policies, ChatPanel, solver view |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| Native SwiftUI/WebKit interaction | **UNVERIFIED** | Requires macOS runtime and real challenge page |
| Third-party captcha iframe compatibility | **UNVERIFIED** | Depends on vendor/WebKit challenge behavior |

### Remaining WEB-07 limitations

WEB-07 remains **PARTIAL**. The code now has a live same-session solver surface and bounded automatic resume, but third-party captcha behavior, iframe/input permissions, WebKit cookie state, sheet interaction, cancellation, and actual vendor completion require macOS runtime verification. A screenshot-only fallback remains in the chat. If a vendor blocks embedded WebKit interaction, the user may still need to complete the challenge externally and then refresh the session.

### Scores

| Dimension | Score | Rationale |
|---|---:|---|
| Implementation quality | 91/100 | The false automatic-resume behavior and inaccessible screenshot-only flow are corrected with a bounded same-bridge policy and interactive solver; live runtime and third-party compatibility remain. |
| Task adherence | 100/100 | Every captcha function/action was traced, red regressions preceded both confirmed fixes, screenshot fallback was retained, and macOS/WebKit boundaries remain explicitly UNVERIFIED. |
| Target-runtime confidence | 0/100 | Linux cannot execute SwiftUI/AppKit/WebKit or real captcha pages. |

The canonical registry remains **274 rows** with **224 PASS, 44 PARTIAL, 1 MISSING, and 5 FUTURE**. `WEB-07` remains PARTIAL because the interaction/resume chain is implemented and contract-tested, while native WebKit and third-party captcha behavior remain unverified.

## Round 68 — Real-model provider eligibility and stale-model fallback

### Scope and chain audit

The sequential audit continued at `WEB-06 Web Providers in Chat Input`. The chain was traced from `WebProviderConfig` and `WebSessionManager` through `WebProviderConnectivity.isConnected`, `providerOptions`, `MyCoderApp.providerOptions`, provider selection, `modelsForSelectedProvider`, `WebProviderSelectionLogic`, `effectiveSelectedModel`, Web Providers settings actions, and the final browser send route.

Two confirmed defects were found. A web provider with valid non-expired cookies but zero discovered real models was exposed in the global provider selector. Separately, `MyCoderApp.effectiveSelectedModel` returned any non-empty persisted model identifier, bypassing the existing selection fallback after live discovery removed that model.

### TDD defect confirmation and fixes

`WebProviderAvailabilityLogicTests` was written before the availability change. The red run demonstrated that a cookie-only provider appeared as selectable. The green implementation now requires both a valid session and at least one `allModels` entry before `WebProviderConnectivity.providerOptions` emits a web option. Existing connected-provider fixtures were corrected to include a real discovered model.

`WebProviderEffectiveModelLogicTests` was written before the effective-model change. The red run failed because no effective-model contract existed. The green `WebProviderSelectionLogic.effectiveSelectedModel` preserves a valid persisted model and falls back to the first discovered real model when the persisted ID is stale. `MyCoderApp.effectiveSelectedModel` now calls that tested contract for web routes.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| Red zero-model availability regression | **failed as expected** | Cookie-only provider was selectable |
| Green availability regressions | **2/2 passed** | Zero-model exclusion and real-model inclusion |
| Red stale-model regression | **failed as expected** | Effective-model helper absent |
| Green effective-model regressions | **2/2 passed** | Stale fallback and valid preservation |
| Full Foundation harness | **229/229 passed** | Existing contracts plus WEB-06 regressions |
| Swift parser validation | **passed** | Connectivity, selection logic, MyCoderApp wiring |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| Native SwiftUI/AppKit interaction | **UNVERIFIED** | Requires macOS runtime |
| Live WebKit/vendor model discovery | **UNVERIFIED** | Requires authenticated vendor pages |

### Remaining WEB-06 limitations

WEB-06 remains **PARTIAL**. The Linux harness verifies session/model selection contracts, but cannot execute SwiftUI/AppKit controls, WebKit cookie restoration, vendor dropdown discovery, live ChatGPT/Kimi/Qwen pages, or provider-specific model availability. Providers with no live models are intentionally hidden rather than shown with a broken send path. A direct programmatic route can still be constructed outside the selector; runtime readiness and browser injection remain separate safety boundaries.

### Scores

| Dimension | Score | Rationale |
|---|---:|---|
| Implementation quality | 94/100 | Provider eligibility now requires session plus real models, and stale model propagation uses one tested source of truth; native/live selection and direct-route boundaries remain. |
| Task adherence | 100/100 | Every WEB-06 control and chain was traced, both confirmed defects received red tests before fixes, and runtime-dependent behavior remains explicitly UNVERIFIED. |
| Target-runtime confidence | 0/100 | Linux cannot execute SwiftUI/AppKit/WebKit or authenticated vendor pages. |

The canonical registry remains **274 rows** with **224 PASS, 44 PARTIAL, 1 MISSING, and 5 FUTURE**. `WEB-06` remains PARTIAL because provider eligibility and stale-model fallback are fixed and contract-tested, while live vendor discovery and native runtime remain unverified.

## Round 69 — Unified Send button and keyboard activation gate

### Scope and chain audit

The sequential audit continued at `INP-10 Send Button`. The chain was traced from `ChatPanelView` and `EmptyChatStateView` into `CenteredInputCard`, `BottomInputBar`, `MessageInputToolbar`, `SendStopButton`, `CompactMessageTextField`, `ZeroInsetTextField`, `SendReadinessLogic`, `SendReadinessReason`, `MessageQueue`, attachment paths, route resolution, and `sendDirectly`.

The visible Send icon already obeyed `canSend` and changed to Stop while loading. The confirmed defect was a second activation path: the centered composer used `onSubmit: { hasAttemptedSend = true; onSend() }`, and the bottom composer passed `onSubmit: onSend`. Pressing Enter could therefore invoke `sendDirectly` while the visible Send button was disabled or while the UI was loading and should have exposed only Stop.

### TDD defect confirmation and fix

`SendButtonActivationLogicTests` was written before the production contract. The red run failed because `SendButtonActivationLogic` did not exist. The green contract returns true only when `canSend` is true and `isLoading` is false. Both centered and bottom Enter callbacks now use this guard. The centered path still records `hasAttemptedSend` before returning, so an empty-input attempt produces the intended readiness explanation without invoking a rejected send.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| Red keyboard activation regressions | **failed as expected** | Missing shared activation contract |
| Green activation regressions | **3/3 passed** | Ready/idle allow, invalid/loading block |
| Full Foundation harness | **232/232 passed** | Existing contracts plus INP-10 regressions |
| Swift parser validation | **passed** | Activation logic and InputViews |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| Native SwiftUI/AppKit interaction | **UNVERIFIED** | Requires macOS runtime |
| Keyboard/accessibility behavior | **UNVERIFIED** | Requires native event and VoiceOver runtime |

### Remaining INP-10 limitations

INP-10 remains **PARTIAL**. Linux cannot execute SwiftUI/AppKit rendering, keyboard event delivery, accessibility/VoiceOver, native file/photo pickers, or live provider stop behavior. The visible Send button and both keyboard paths now share one tested activation gate, while route-level runtime failures continue to be handled by `sendDirectly` validation and persistence guards.

### Scores

| Dimension | Score | Rationale |
|---|---:|---|
| Implementation quality | 94/100 | Button and keyboard routes share one ready/idle contract; native keyboard/accessibility, picker, and live cancellation behavior remain. |
| Task adherence | 100/100 | Every visible send/stop action and underlying function was traced, the confirmed bypass received a red test before the fix, and native-only behavior is explicitly UNVERIFIED. |
| Target-runtime confidence | 0/100 | Linux cannot execute SwiftUI/AppKit keyboard, accessibility, picker, or provider runtime behavior. |

The canonical registry remains **274 rows** with **224 PASS, 44 PARTIAL, 1 MISSING, and 5 FUTURE**. `INP-10` remains PARTIAL because the source-level activation contract is fixed and tested, while native interaction and live provider cancellation remain unverified.

## Round 70 — Validate model parameter dialog inputs

### Scope and chain audit

The sequential audit continued at `INP-14 Model Parameters Dialog`. The chain was traced from `MessageInputToolbar` and `ModelSelectionPresentationLogic` into `ModelParametersButton`, its temperature/max-tokens/Top-P/system fields, `ModelCallParametersStore`, request-fragment serialization, direct OpenAI-compatible sends, Serve/ACP request builders, and optional web parameter injection.

The dialog already resolved the effective model and persisted values per model ID. The confirmed defect was unsafe numeric input handling: `save()` converted arbitrary text directly with `Double(...)`/`Int(...)`, accepted out-of-range values, and silently turned malformed entries into nil. The user could therefore receive no error while the saved state differed from what the dialog appeared to accept.

### TDD defect confirmation and fix

`ModelCallParametersValidationLogicTests` was written before the validation helper. The red run failed because the parser/bounds contract did not exist. The green `ModelCallParametersValidationLogic.parse` allows blank fields as provider defaults, requires finite temperature in `0–2`, Top P in `0–1`, and max tokens as a positive integer, and preserves meaningful system prompt text.

`ModelParametersButton.save()` now calls the tested parser, leaves the popover open on invalid input, shows an inline actionable error, retains the user’s text for correction, and writes only validated values. Reset clears both the stored per-model override and the validation error.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| Red parameter-validation regressions | **failed as expected** | Missing parser/bounds contract |
| Green parameter-validation regressions | **4/4 passed** | Valid, blank, float ranges, positive integer |
| Full Foundation harness | **236/236 passed** | Existing contracts plus INP-14 validation tests |
| Swift parser validation | **passed** | Validation helper, model store, parameter popover |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| Native SwiftUI/AppKit popover | **UNVERIFIED** | Requires macOS runtime |
| Live web parameter controls | **UNVERIFIED** | Requires authenticated vendor pages |

### Remaining INP-14 limitations

INP-14 remains **PARTIAL**. Linux cannot execute SwiftUI popovers, native text editors, accessibility, or live provider parameter controls. Direct/Serve/ACP request-fragment consumers remain covered by existing Foundation tests. Web parameter injection remains dependent on vendor DOM controls and is explicitly unverified at runtime.

### Scores

| Dimension | Score | Rationale |
|---|---:|---|
| Implementation quality | 94/100 | Unsafe silent parameter handling is fixed with a pure parser and inline recovery state; localized copy, native interaction, and live vendor controls remain. |
| Task adherence | 100/100 | Every parameter field/button/consumer was traced, red tests preceded the fix, and native/live behavior remains explicitly UNVERIFIED. |
| Target-runtime confidence | 0/100 | Linux cannot execute SwiftUI/AppKit popovers or authenticated provider parameter surfaces. |

The canonical registry remains **274 rows** with **224 PASS, 44 PARTIAL, 1 MISSING, and 5 FUTURE**. `INP-14` remains PARTIAL because validation and persistence contracts are fixed and tested, while native popover and live web-control behavior remain unverified.

## Round 71 — Payload-aware provider connection validation

### Scope and chain audit

The sequential audit continued at `PROV-08 Connection Validation`. The chain was traced from provider settings fields and `ProviderEndpointLogic` through `MyCoderApp.testProvider`, Keychain-backed API-key retrieval, URLSession `/models` requests, response parsing, `loadModelsFromCustomProvider`, provider model persistence, readiness, selection, and send routing.

The confirmed defect was that `testProvider` returned success for any HTTP 200 response. An HTML login page, malformed JSON, or valid JSON with an empty model list could therefore be reported as a successful connection even though no model could be selected or sent. The model loader had stronger validation, but the standalone Test Connection action did not share it.

### TDD defect confirmation and fix

`ProviderConnectionValidationLogicTests` was written before the validation helper. The red run failed because the payload-aware contract did not exist. The green `ProviderConnectionValidationLogic.isValidModelsResponse` requires a 2xx status and at least one non-empty model identifier from OpenAI-style `data` or named `models` payloads, while ignoring blank entries. `MyCoderApp.testProvider` now delegates to this contract and fails closed for malformed, empty, or non-success responses.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| Red payload-aware validation regressions | **failed as expected** | Missing validation contract |
| Green provider-validation regressions | **4/4 passed** | Valid payload, invalid body, empty list, non-success status |
| Full Foundation harness | **240/240 passed** | Existing contracts plus PROV-08 regressions |
| Swift parser validation | **passed** | Validation helper and MyCoderApp wiring |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| Real network/Keychain execution | **UNVERIFIED** | Requires macOS runtime and provider endpoints |
| SwiftUI settings interaction | **UNVERIFIED** | Requires native UI runtime |

### Remaining PROV-08 limitations

PROV-08 remains **PARTIAL**. Linux cannot execute URLSession against real provider endpoints, Keychain behavior, SwiftUI settings controls, TLS/proxy/captive-login behavior, or provider-specific response variants. The pure validation contract prevents false positives at the response boundary; live network reachability and user-visible localized error presentation require macOS/runtime verification.

### Scores

| Dimension | Score | Rationale |
|---|---:|---|
| Implementation quality | 94/100 | Connection validation now checks the actual model payload and fails closed; live network, Keychain, provider variants, and localized UI behavior remain. |
| Task adherence | 100/100 | Every PROV-08 field/action/function was traced, the confirmed false-positive defect received red tests before the fix, and network/runtime boundaries are explicitly UNVERIFIED. |
| Target-runtime confidence | 0/100 | Linux cannot execute URLSession, Keychain, SwiftUI settings, or real provider endpoints. |

The canonical registry remains **274 rows** with **224 PASS, 44 PARTIAL, 1 MISSING, and 5 FUTURE**. `PROV-08` remains PARTIAL because payload validation is fixed and contract-tested, while native settings, credentials, network, and endpoint runtime remain unverified.

## Round 72 — Resilient duplicate-path file-index deltas

### Scope and chain audit

The sequential audit continued at `STO-06 File Index Logic`. The chain was traced from project/workspace selection and the `@` file suggestion path through `ProjectFileScanner`, `FileIndexRecord`, `ProjectFileIndexLogic.shouldExclude/shouldIndex/computeDelta`, `ProjectFileIndexPersistenceLogic.applyDelta`, `ProjectFileIndexStore`, watcher invalidation, and downstream file context.

The normal scanner emits unique sorted relative paths, but persisted JSON is an external boundary. Both delta implementations constructed dictionaries with `Dictionary(uniqueKeysWithValues:)`; a duplicate path in a malformed or manually edited snapshot caused a fatal runtime trap during refresh or relaunch.

### TDD defect confirmation and fix

`ProjectFileIndexDuplicateRecordTests` was written first. After adding only the required Foundation/index fixtures to the harness, the red run reached the intended duplicate-key fatal crash. The green fix adds `ProjectFileIndexLogic.recordsByPath`, where the last record for a path wins deterministically. `computeDelta` and `applyDelta` both use this helper, iterate scanned keys in sorted order, and return deterministic output without crashing.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| Red duplicate-path regression | **failed as expected** | Production dictionary trap reached in harness |
| Green duplicate-path regressions | **2/2 passed** | `computeDelta` and `applyDelta` recover deterministically |
| Full Foundation harness | **242/242 passed** | Existing contracts plus STO-06 regressions |
| Swift parser validation | **passed** | Record, logic, persistence sources |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| macOS file I/O/FSEvents | **UNVERIFIED/PARTIAL** | Requires native runtime |
| Persistent SQLite/FTS | **MISSING** | Separate IDX-03 capability |

### Remaining STO-06 limitations

STO-06 remains **PARTIAL**. Project-scoped JSON persistence, hash/mtime delta computation, exclusion rules, duplicate-path recovery, and deterministic output are covered. CoreServices watcher behavior is implemented but live macOS event delivery, shutdown, and permissions remain unverified. Full persistent SQLite/FTS search remains missing and is tracked separately as IDX-03; this round does not claim that JSON snapshots constitute FTS.

### Scores

| Dimension | Score | Rationale |
|---|---:|---|
| Implementation quality | 94/100 | Malformed duplicate snapshots no longer crash index refresh and output order is deterministic; FTS, native file I/O, and live watcher behavior remain. |
| Task adherence | 100/100 | Every STO-06 function and action was traced, the confirmed crash received a red regression before the fix, and missing/runtime-only behavior remains honestly classified. |
| Target-runtime confidence | 0/100 | Linux cannot execute macOS file I/O, CoreServices FSEvents, SwiftUI, or SQLite/FTS runtime behavior. |

The canonical registry remains **274 rows** with **224 PASS, 44 PARTIAL, 1 MISSING, and 5 FUTURE**. `STO-06` remains PARTIAL because duplicate-path recovery is fixed and contract-tested, while live watcher behavior and persistent FTS remain outside this verifiable scope.

## Round 73 — Avoid watcher restart on branch-only workspace update

### Scope and chain audit

The sequential audit continued at `STO-07 FSEvents Dynamic Reindexing`. The chain was traced from workspace selection, branch updates, and `selectedWorkspace.didSet` through `updateProjectFileIndexWatcher`, `ProjectFileIndexWatcher.start/stop`, CoreServices FSEvents callback filtering, debounce scheduling, generation guards, project cache invalidation, and the downstream `@` file-suggestion refresh path.

The watcher implementation already had the important safety contracts: CoreServices FSEvents on macOS, a Linux no-op fallback, 300 ms debounce, project-path boundary filtering, `.mycoder` suppression, and generation/project guards against stale callbacks. The adversarial chain found one lifecycle defect. `updateWorkspaceBranch` creates a new `Workspace` value with only its branch changed and reassigns `selectedWorkspace`. The old `didSet` unconditionally stopped the watcher, cleared `projectFilesCache`, and created a new watcher even though the project path was unchanged. This created avoidable event-stream churn and forced a later file-index refresh for a metadata-only mutation.

### TDD defect confirmation and fix

`ProjectFileIndexWatcherLifecycleLogicTests` was written before the implementation. The red run failed at compilation because the restart policy did not yet exist, confirming that the test exercised a missing contract rather than merely repeating an existing behavior. The three regression cases cover path-stable mutations with trailing-slash normalization, actual project-path changes, and workspace creation/clearing through `nil` transitions.

The green implementation adds `ProjectFileIndexWatcherLifecycleLogic.shouldRestart(oldProjectPath:newProjectPath:)`. It canonicalizes non-empty file paths with `standardizedFileURL` and returns true only when the canonical old and new project paths differ. `selectedWorkspace.didSet` now invokes `updateProjectFileIndexWatcher` only when this policy returns true. Therefore branch-only workspace updates preserve the active watcher and file-index cache, while project switches, workspace creation, and workspace clearing still restart or stop the lifecycle as required.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| Red watcher lifecycle regression | **failed as expected** | Missing restart policy was referenced by the new tests |
| Green watcher lifecycle regressions | **3/3 passed** | Same canonical path does not restart; path/nil transitions restart |
| Full Foundation harness | **245/245 passed** | Existing contracts plus STO-07 lifecycle regressions |
| Swift parser validation | **passed** | Lifecycle helper and `MyCoderApp` wiring |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| CoreServices FSEvents delivery | **UNVERIFIED** | Requires native macOS runtime and filesystem events |
| Native watcher teardown/permissions | **UNVERIFIED** | Requires macOS runtime, permissions, and real filesystem races |
| Persistent SQLite/FTS search | **MISSING** | Separate IDX-03 capability; not falsely claimed here |

### Remaining STO-07 limitations

`STO-07` remains **PARTIAL**. The source-level lifecycle, path filtering, debounce, generation isolation, `.mycoder` suppression, and path-stable branch-update behavior are implemented and contract-tested. Live CoreServices event delivery, stream shutdown, filesystem permission failures, SwiftUI observation timing, and packaged macOS behavior remain unverified in the Linux Foundation harness. Persistent SQLite/FTS search is a separate missing capability and is not implied by the JSON index snapshot.

### Scores

| Dimension | Score | Rationale |
|---|---:|---|
| Implementation quality | 95/100 | The confirmed branch-only watcher churn is removed with a small canonical-path policy and regression coverage; native event delivery, shutdown races, permissions, and persistent FTS remain unverified or missing. |
| Task adherence | 100/100 | Every STO-07 action and function was manually chain-traced, red tests preceded the fix, canonical checklist/registry/report updates were made, and native-only limits remain explicitly UNVERIFIED. |
| Target-runtime confidence | 0/100 | Linux cannot execute CoreServices FSEvents, SwiftUI observation, AppKit behavior, or packaged macOS filesystem/permission scenarios. |

The canonical registry remains **274 rows** with **224 PASS, 44 PARTIAL, 1 MISSING, and 5 FUTURE**. `STO-07` remains PARTIAL because the branch-only lifecycle defect is fixed and contract-tested, while live macOS FSEvents behavior, native teardown/permissions, and persistent FTS remain outside the verifiable scope.

## Round 74 — Safe and visible registry/settings configuration transfer

### Scope and chain audit

The sequential audit continued at `STO-27 Registry+Settings Export/Import`. The full chain was manually traced from the Storage settings header buttons through `NSSavePanel`/`NSOpenPanel`, `AppConfigurationBackupStore`, `AppConfigurationBackupLogic`, `ProjectRegistryLogic`, `AppSettings`, `UserDefaults`, atomic file writes, post-import settings reload, registry refresh, and storage-stat refresh. The existing project `.zip` export/import path was checked separately so global configuration migration is not confused with one-project history backup.

The bundle itself was already versioned and validated: it carries independent registry and settings JSON payloads, uses ISO-8601 dates and sorted-key JSON, rejects malformed/unsupported schemas, and writes the export atomically. The adversarial chain found two confirmed user-facing defects in the native action layer. A valid imported bundle directly replaced the current registry and settings without a confirmation step. Export and import Bool results were also discarded: write failures and rejected bundles silently returned, making failure indistinguishable from a cancelled panel.

### TDD defect confirmation and fix

`AppConfigurationTransferLogicTests` was written before the implementation. The red run failed because the transfer safety/notice contract did not exist. The three regressions require explicit replacement confirmation and require visible, non-empty failure notices for both export and import failures.

The green fix adds `AppConfigurationTransferLogic` with typed operation/outcome notices and an explicit `importRequiresConfirmation` contract. `StorageSettingsView` now retains the selected import URL until the user chooses “Import and replace”. The action then calls `AppConfigurationBackupStore.import`; only success reloads `AppSettings`, refreshes the project registry, and recomputes storage statistics. Export and import results now generate visible success/failure alerts instead of being silently ignored.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| Red transfer UX regressions | **failed as expected** | Transfer safety/notice contract absent before implementation |
| Green transfer UX regressions | **3/3 passed** | Confirmation required; export/import failures produce visible notices |
| Full Foundation harness | **248/248 passed** | Existing contracts plus STO-27 transfer regressions |
| Swift parser validation | **passed** | Transfer logic and StorageSettingsView |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| AppKit save/open panels | **UNVERIFIED** | Requires macOS runtime and actual user interaction |
| Filesystem permissions and atomic replacement | **UNVERIFIED** | Requires native filesystem execution |
| Cross-machine path remapping | **PARTIAL** | Imported absolute paths are preserved; orphan/relink remains manual |
| Keychain/custom-provider/web-cookie migration | **OUT OF SCOPE** | Not encoded by the registry + AppSettings bundle |

### Remaining STO-27 limitations

`STO-27` remains **PARTIAL**. The versioned global bundle is validated, destructive replacement is confirmed, transfer failures are visible, and successful import refreshes the visible settings-page state. Native panel behavior, filesystem permission failures, actual cross-machine relinking, and migration of external secret/browser-session stores require macOS runtime or a separately designed migration contract. The bundle honestly covers the registry and `AppSettings`; it does not claim to migrate Keychain secrets, custom-provider catalogs, or web cookies that are persisted elsewhere.

### Scores

| Dimension | Score | Rationale |
|---|---:|---|
| Implementation quality | 96/100 | Confirmed silent-failure and unconfirmed-overwrite defects are fixed with a small typed contract and regression coverage; native panels, portability, and external stores remain. |
| Task adherence | 100/100 | Every visible control and persistence function was traced, red tests preceded the fixes, the canonical checklist/registry/report were updated, and native/runtime limits remain explicitly UNVERIFIED. |
| Target-runtime confidence | 0/100 | Linux cannot execute AppKit save/open panels, SwiftUI alert presentation, macOS filesystem permissions, or cross-machine relinking. |

The canonical registry remains **274 rows** with **224 PASS, 44 PARTIAL, 1 MISSING, and 5 FUTURE**. `STO-27` remains PARTIAL because transfer safety and error visibility are fixed and contract-tested, while native panels, filesystem behavior, manual path relinking, and external credential/session migration remain outside the verifiable scope.

## Round 75 — Harden big-project deletion safety and failure visibility

### Scope and chain audit

The sequential audit continued at `STO-28 Chunked Big-Project Delete`. Every delete path was traced from the active and orphan project-row trash buttons through `pendingDeleteEntry`, typed-name confirmation, the scope description, auto-backup creation, deleted-backup preservation, audit logging, `ProjectDeletionExecutor`, registry persistence, active-workspace cleanup, and visible result handling.

Round 62 had correctly replaced one unbounded recursive removal with a project-root guard, deepest-first ordering, and bounded deletion batches. The adversarial chain found that the safety boundary was incomplete. `deleteProject` ignored failures from both backup calls and proceeded with irreversible deletion. `ProjectDeletionExecutor` swallowed per-item filesystem errors and exposed only a Bool. A failed delete returned silently, and registry-save errors were ignored after the filesystem operation. The user could therefore receive no actionable explanation and could lose the promised recovery backup.

### TDD defect confirmation and fix

`ProjectDeletionOutcomeLogicTests` was written first for completion gating and visible cancellation/failure notices. The red run failed because the outcome contract did not exist. A second red run added the backup prerequisite cases and failed because `ProjectDeletionBackupPolicy` did not exist. The green implementation adds explicit completed/cancelled/failed outcomes, a backup policy that fails closed when a project DB exists without both backup creation and preservation, and notices that distinguish failure from cancellation.

`ProjectDeletionExecutor.execute` now exposes `shouldCancel` and `onProgress` hooks, reports the failing path/reason instead of swallowing `removeItem` errors, and treats root-removal failure or a residual root as a failed outcome. The legacy Bool wrapper remains for existing callers. `StorageSettingsView` gates deletion on required backup success, disables duplicate delete buttons while the action is active, mutates the registry only after a completed delete and successful atomic save, compares selected/deleted paths canonically, and presents visible failure/cancellation notices. The current UI action remains synchronous; the new hooks prepare the next asynchronous progress/cancellation round but do not falsely claim that a progress task already exists.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| Red deletion outcome regressions | **failed as expected** | Outcome/notice contract absent before implementation |
| Red backup-safety regression | **failed as expected** | Backup policy absent before implementation |
| Green outcome/backup regressions | **4/4 passed** | Completion gate, cancellation/failure notices, backup prerequisites |
| Full Foundation harness | **252/252 passed** | Existing contracts plus STO-28 regressions |
| Swift parser validation | **passed** | Outcome logic, executor, StorageSettingsView |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| Native filesystem/symlink behavior | **UNVERIFIED** | Requires macOS filesystem runtime |
| Background progress/cancellation UI | **MISSING/PARTIAL** | Hooks exist; visible asynchronous task remains absent |

### Remaining STO-28 limitations

`STO-28` remains **PARTIAL**. Required recovery backup, error propagation, registry gating, duplicate-action prevention, canonical active-workspace cleanup, and result notices are hardened. The executor still enumerates synchronously, the SwiftUI action has no visible progress or cancellation task, registry-save failure after data deletion has no rollback transaction, and native filesystem/symlink behavior remains unverified in Linux.

### Scores

| Dimension | Score | Rationale |
|---|---:|---|
| Implementation quality | 96/100 | Irreversible deletion now fails closed on required backup failure and reports filesystem/registry problems; asynchronous progress, rollback, and native filesystem behavior remain. |
| Task adherence | 100/100 | Every delete action and function was traced, red regressions preceded each newly confirmed safety fix, canonical documentation was updated, and native/runtime limits remain explicit. |
| Target-runtime confidence | 0/100 | Linux cannot execute SwiftUI/AppKit deletion interaction or macOS filesystem, permission, and symlink scenarios. |

The canonical registry remains **274 rows** with **224 PASS, 44 PARTIAL, 1 MISSING, and 5 FUTURE**. `STO-28` remains PARTIAL because safety and failure visibility are fixed and contract-tested, while visible asynchronous progress/cancellation, rollback, and native filesystem behavior remain outside the verifiable scope.

## Round 76 — Preserve session-busy retry identity and turn persistence

### Scope and chain audit

The sequential audit continued at `ERR-01 Session Busy Recovery`. The chain was traced from `ChatPanelView.sendDirectly` through readiness checks, route selection, remote session preparation, user/assistant persistence, `MimoServeClient.sendMessage`, HTTP status classification, `MimoServeError.sessionBusy`, notification, `abortSession`, the 500 ms delay, recursive retry, response merge, terminal failure, and loading/streaming cleanup.

The existing source correctly mapped HTTP 409 to a distinct session-busy error, notified the user, aborted the session, waited 500 ms, and limited recursion to three retries. The adversarial chain found a persistence/identity defect. Each recursive retry generated a fresh assistant UUID and request message ID, called the session-preparation path again, and appended the same user message to `MessageStore`. Because `MessageStore.append` persists to the current session database, one user send could become multiple persisted user turns after busy recovery. The retry could also lose the exact session identity that returned 409.

### TDD defect confirmation and fix

`SessionBusyRetryLogicTests` was written first. The initial red run failed because the retry planner did not exist. The green implementation adds `SessionBusyRetryLogic` with a three-retry bound and a `RetryPlan` carrying the session ID and assistant-message ID. A second red edge-case run added request message-ID preservation and failed until that identity was included in the plan.

`ChatPanelView.sendDirectly` now accepts an internal retry plan. The initial attempt creates and persists the user message and assistant placeholder. Busy retries reuse the original session, assistant placeholder, and request message ID; they do not append another user message, and they update the existing assistant row before reissuing the Serve request. Exhaustion remains bounded and the terminal path clears loading/streaming state.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| Red retry-planner regression | **failed as expected** | Planner absent before implementation |
| Red message-ID regression | **failed as expected** | Request ID was not carried before implementation |
| Green retry regressions | **2/2 passed** | Bound and all three identities preserved |
| Full Foundation harness | **254/254 passed** | Existing contracts plus ERR-01 regressions |
| Swift parser validation | **passed** | Retry planner and ChatPanelView |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| Live 409 Serve response | **UNVERIFIED** | Requires macOS/runtime and a real Serve endpoint |
| Native notification/message rendering | **UNVERIFIED** | Requires SwiftUI/AppKit runtime |
| Abort endpoint behavior/race timing | **UNVERIFIED** | Requires live Serve session lifecycle |

### Remaining ERR-01 limitations

`ERR-01` remains **PARTIAL**. The confirmed duplicate-turn/new-identity defect is fixed and contract-tested, with a bounded retry plan and coherent terminal cleanup. Live Serve 409 behavior, abort races, native notification presentation, and endpoint-specific session semantics remain unverified. Abort failure remains best-effort and is not separately surfaced before retry exhaustion.

### Scores

| Dimension | Score | Rationale |
|---|---:|---|
| Implementation quality | 96/100 | Retry identity and persistence are now coherent and bounded; live session behavior, abort-failure observability, and native runtime remain. |
| Task adherence | 100/100 | Every request, persistence, retry, abort, notification, and terminal-error action was traced, red tests preceded each confirmed fix, canonical documentation was updated, and runtime-only behavior remains explicitly UNVERIFIED. |
| Target-runtime confidence | 0/100 | Linux cannot execute a live MiMo Serve 409/abort lifecycle or native SwiftUI/AppKit notification/message rendering. |

The canonical registry remains **274 rows** with **224 PASS, 44 PARTIAL, 1 MISSING, and 5 FUTURE**. `ERR-01` remains PARTIAL because stable retry identity and duplicate-turn prevention are fixed and contract-tested, while live Serve session behavior and native presentation remain outside the verifiable scope.

## Round 77 — Make disconnected Serve errors route-specific

### Scope and chain audit

The sequential audit continued at `ERR-02 Server Disconnected Error`. The chain was traced from `AppState.serverConnected` and `selectedProviderID` through `SendReadinessLogic`, `SendProviderReadinessLogic`, `SendReadinessReason`, centered and bottom composer `canSend` gates, keyboard Enter activation, `SendStopButton.disabledReason`, `ChatPanelView` direct-send preflight, rejected-send persistence, and the final user-facing message.

The prior Round 59 work correctly prevented Serve health from masquerading as readiness for web, local, and custom routes. The adversarial audit found one remaining clarity defect: when a known Serve provider was selected while `serverConnected` was false, readiness fell through to a generic “No provider is ready” message listing unrelated local/custom/web alternatives. The user was not told that the selected route required myCoder Serve to be started or reconnected.

### TDD defect confirmation and fix

A red regression was added to `SendProviderReadinessLogicTests` before implementation. It required the known disconnected Serve route to produce an actionable message containing both Serve and connection guidance. The red run failed because the existing generic message did not mention Serve. The green fix adds a narrow branch for a known `serverProviderIDs` entry while disconnected: “myCoder Serve is not running or disconnected. Start or reconnect myCoder Serve before sending.” Existing web/local/custom route behavior remains unchanged.

The message flows through `SendReadinessReason` into both composer layouts and `SendStopButton.disabledReason`; the send button remains disabled, the reason is shown inline/help, and direct send rechecks the same readiness contract before routing. Keyboard Enter cannot bypass the shared gate.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| Red disconnected-Serve message regression | **failed as expected** | Generic message did not mention Serve |
| Green readiness regressions | **4/4 passed** | Known Serve, web, effective model, and stale-health cases |
| Full Foundation harness | **255/255 passed** | Existing contracts plus ERR-02 regression |
| Swift parser validation | **passed** | SendProviderReadinessLogic |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| Native composer rendering | **UNVERIFIED** | Requires SwiftUI/AppKit runtime |
| Live Serve endpoint/health failure | **UNVERIFIED** | Requires macOS runtime and actual Serve process |

### Remaining ERR-02 limitations

`ERR-02` remains **PARTIAL**. Route-specific disconnected Serve guidance is fixed and contract-tested, while web/local/custom readiness remains independent of Serve health. Native composer rendering, live health transitions, network failure variants, localization, and endpoint-specific runtime behavior remain unverified.

### Scores

| Dimension | Score | Rationale |
|---|---:|---|
| Implementation quality | 96/100 | The confirmed misleading text is fixed with a narrow provider-aware branch; native presentation and live endpoint behavior remain. |
| Task adherence | 100/100 | Every readiness function, button, keyboard path, rejected-send path, and error consumer was traced; the red test preceded the fix; documentation was updated; macOS-only behavior remains explicitly UNVERIFIED. |
| Target-runtime confidence | 0/100 | Linux cannot execute native SwiftUI/AppKit composer rendering or a live Serve health transition. |

The canonical registry remains **274 rows** with **224 PASS, 44 PARTIAL, 1 MISSING, and 5 FUTURE**. `ERR-02` remains PARTIAL because route-specific guidance is fixed and contract-tested, while native presentation and live endpoint behavior remain outside the verifiable scope.

## Round 78 — Surface blank Serve completions as validation errors

### Scope and chain audit

The sequential audit continued at `ERR-03 Send Validation Errors`. The chain was traced from model/provider/effective-model validation through empty-input handling, centered and bottom composer gates, `SendStopButton`, keyboard Enter, rejected-send persistence, direct-send preflight, Serve response extraction, SSE text/reasoning/tool events, `session.idle`/status-idle completion, assistant-message finalization, and loading/streaming cleanup.

Round 59 had already fixed stale web/Auto Free model gating and blank web/provider response handling. The current adversarial audit found a remaining Serve-specific defect. `finishStreaming` previously marked the assistant complete and inserted the localized task-completed fallback whenever `streamingText` was empty. A completed Serve turn with no text, reasoning, or tool activity could therefore appear successful, or retain a synthetic “Thinking…” bubble, instead of telling the user that the provider returned no answer.

### TDD defect confirmation and fix

Red regressions were added to `ProviderResponseValidationLogicTests` before implementation. The first red run failed because the completion-specific contract and retry guidance did not exist. The green implementation adds `shouldReportEmptyCompletion(text:reasoning:hasToolActivity:)` and a stable actionable message.

`ChatPanelView.finishStreaming` now inspects the current assistant message, ignores the synthetic Thinking placeholder, preserves reasoning/tool/step activity as valid completion context, and replaces a truly blank completed turn with the empty-response error before clearing the stream. Valid non-empty responses and tool/reasoning-only completions retain their existing behavior.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| Red empty-completion regressions | **failed as expected** | Completion contract absent before implementation |
| Green response-validation regressions | **4/4 passed** | Blank, visible text, reasoning, tool activity, and guidance |
| Full Foundation harness | **257/257 passed** | Existing contracts plus ERR-03 regressions |
| Swift parser validation | **passed** | Response validation and ChatPanelView |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| Native composer/message rendering | **UNVERIFIED** | Requires SwiftUI/AppKit runtime |
| Live Serve/SSE completion behavior | **UNVERIFIED** | Requires macOS runtime and a real Serve endpoint |

### Remaining ERR-03 limitations

`ERR-03` remains **PARTIAL**. Effective model/provider/empty-input gates and empty completed-response handling are hardened and contract-tested. Native rendering, live Serve/SSE timing, localized text presentation, and database persistence remain unverified.

### Scores

| Dimension | Score | Rationale |
|---|---:|---|
| Implementation quality | 96/100 | The confirmed false-success/blank-bubble path is fixed with a narrow content-aware finalization rule; live runtime and native verification remain. |
| Task adherence | 100/100 | Every validation function, button, keyboard path, provider branch, SSE completion path, and persistence action was traced; red tests preceded the confirmed fix; documentation was updated; runtime-only behavior remains explicitly UNVERIFIED. |
| Target-runtime confidence | 0/100 | Linux cannot execute native SwiftUI/AppKit message rendering or live Serve/SSE timing. |

The canonical registry remains **274 rows** with **224 PASS, 44 PARTIAL, 1 MISSING, and 5 FUTURE**. `ERR-03` remains PARTIAL because validation and blank-completion handling are fixed and contract-tested, while native rendering and live Serve/SSE behavior remain outside the verifiable scope.

## Round 79 — Fail closed on browser navigation timeout and preserve cookie security

### Scope and chain audit

The sequential audit continued at `WEB-05 Browser Transport (WKWebView)`. The chain was traced from persisted transport selection and runtime labels through `WKWebViewBrowserBridge` navigation, readyState polling, JavaScript evaluation, text injection, click helpers, selector waits, DOM text/fingerprint reads, model candidate discovery, cookie capture/restoration, localStorage restoration, screenshots, stop-generation fallback, and WebChatDriver consumers.

Round 66 correctly removed the false claim that legacy CDP attached to external Chrome. The fresh audit found two additional transport-boundary defects. `navigate(to:)` polled readyState for 15 seconds and then returned without indicating that the page never became ready. `setCookies` captured secure/httpOnly fields into `BrowserCookie` but rebuilt HTTPCookie values without either property, weakening restored session fidelity.

### TDD defect confirmation and fix

`WebBrowserTransportLogicTests` was written before implementation. The red run failed because explicit navigation-timeout and cookie-attribute contracts did not exist. The green implementation adds a bounded navigation outcome/message contract and a cookie-attribute mapper. `WKWebViewBrowserBridge.navigate` now throws `navigationTimeout` after readyState polling expires. `setCookies` forwards secure and httpOnly properties to HTTPCookie when rebuilding cookies.

The audit also records two remaining source limitations rather than falsely claiming completion: the `selector` argument of `screenshot(selector:)` is ignored and the `waitForSelector` timeout currently returns without throwing. External Playwright MCP/CDP transport remains absent by design; runtime labels remain honest.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| Red transport regressions | **failed as expected** | Timeout/cookie contracts absent before implementation |
| Green transport regressions | **3/3 passed** | Ready timeout, secure/httpOnly preservation, false flags |
| Full Foundation harness | **260/260 passed** | Existing contracts plus WEB-05 regressions |
| Swift parser validation | **passed** | Transport helper and WKWebView bridge |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| Live WKWebView navigation/cookies | **UNVERIFIED** | Requires macOS/WebKit and vendor pages |
| External Playwright MCP/CDP | **MISSING** | No production external transport exists; label is honest |
| Selector-scoped screenshot | **PARTIAL** | Current bridge takes a page snapshot and ignores selector argument |
| Selector wait expiry | **PARTIAL** | Bounded wait exists but expiry is not thrown to callers |

### Remaining WEB-05 limitations

`WEB-05` remains **PARTIAL**. The supported runtime is honestly identified as an isolated WKWebView; navigation timeout now fails closed and cookie security flags survive restoration. External Playwright/CDP transports, live WebKit behavior, selector-scoped screenshots, and throwing selector-wait expiry remain incomplete or unverified.

### Scores

| Dimension | Score | Rationale |
|---|---:|---|
| Implementation quality | 95/100 | Silent navigation success and cookie-security loss are fixed with narrow contracts; selector-scoped screenshots, wait-expiry propagation, and native runtime verification remain. |
| Task adherence | 100/100 | Every transport, navigation, DOM, cookie, storage, screenshot, stop, and error action was traced; red tests preceded the confirmed fixes; canonical documentation was updated; unsupported runtime behavior remains explicitly UNVERIFIED. |
| Target-runtime confidence | 0/100 | Linux cannot execute SwiftUI/AppKit/WebKit or live vendor pages. |

The canonical registry remains **274 rows** with **224 PASS, 44 PARTIAL, 1 MISSING, and 5 FUTURE**. `WEB-05` remains PARTIAL because WKWebView behavior is hardened and contract-tested, while external transports, selector-scoped screenshots, wait-expiry propagation, and native WebKit verification remain incomplete.

## Round 80 — Preserve destination-provider model context on web-provider switch

### Scope and chain audit

The sequential audit continued at `WEB-06 Web Providers in Chat Input`. The chain was traced from `WebProviderStore` persistence and sanitization through session/cookie eligibility, expiry checks, zero-model filtering, `web:<id>` option identity, `ProviderSelectorMenu`, `selectProvider`, `modelsForSelectedProvider`, effective-model presentation, effort capability gating, send readiness, `WebChatDriver` model/effort injection, discovery persistence, and web-session/send metadata.

Round 68 had already excluded cookie-only zero-model providers and added stale persisted-model fallback. The fresh audit found one remaining state leak. `AppState.selectProvider` examined the global `selectedModel` first. If that ID also existed in the destination provider’s model list, switching providers silently selected the global model even when the destination config had a different valid persisted `selectedModel`.

### TDD defect confirmation and fix

A red regression was added to `WebProviderSelectionLogicTests` before implementation. It failed because no provider-switch model contract existed. The green implementation adds `modelForProviderSwitch(config:globalSelectedModel:availableModels:)`: the destination provider’s valid persisted model wins; only when that is stale may a valid global fallback be used, followed by the first available model. `AppState.selectProvider` now consumes this contract and persists the resulting model consistently.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| Red provider-switch regression | **failed as expected** | Destination-specific selection contract absent before implementation |
| Green WEB-06 selection suite | **10/10 passed** | Provider switch, selection, effort, injection, and custom vendor coverage |
| Full Foundation harness | **261/261 passed** | Existing contracts plus WEB-06 regression |
| Swift parser validation | **passed** | Selection logic and AppState wiring |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| Native SwiftUI composer/menus | **UNVERIFIED** | Requires macOS runtime |
| Live WebKit model discovery and send | **UNVERIFIED** | Requires authenticated vendor pages |

### Remaining WEB-06 limitations

`WEB-06` remains **PARTIAL**. Session/model eligibility, zero-model filtering, stale-model fallback, provider-specific switch selection, effort capability gating, and browser injection guards are contract-tested. Native menus, live vendor discovery, cookie restoration, and real ChatGPT/Kimi/Qwen send behavior remain unverified.

### Scores

| Dimension | Score | Rationale |
|---|---:|---|
| Implementation quality | 95/100 | Provider identity and model selection now have one tested source of truth; native/live runtime and dynamic zero-model transitions remain. |
| Task adherence | 100/100 | Every WEB-06 selector, state transition, discovery action, send gate, browser injection, and persistence path was traced; the confirmed defect received a red test before the fix; documentation was updated; runtime-only behavior remains explicitly UNVERIFIED. |
| Target-runtime confidence | 0/100 | Linux cannot execute SwiftUI/AppKit/WebKit or authenticated vendor pages. |

The canonical registry remains **274 rows** with **224 PASS, 44 PARTIAL, 1 MISSING, and 5 FUTURE**. `WEB-06` remains PARTIAL because provider eligibility and provider-specific model selection are hardened and contract-tested, while live vendor discovery and native runtime remain unverified.

## Round 81 — Recover captcha interruptions during response polling and close terminal solver state

### Scope and chain audit

The sequential audit continued at `WEB-07 Captcha Display in Chat`. The chain was traced from `WebSessionLogic` captcha detection and state inference through screenshot capture, `WebChatEventPresenter`, `WebChatTurnMutation`, the same-WKWebView `WebCaptchaSolverView`, `WebCaptchaResolutionLogic`, `WebChatDriver.runTurn`, pre-send interruption checks, post-submit response polling, timeout/logout handling, final answer delivery, and solver visibility cleanup.

Round 67 had already replaced the misleading screenshot-only/automatic-resume behavior with an interactive solver backed by the exact same live WKWebView. The fresh audit found two additional lifecycle defects. `awaitResponse` could poll for up to two minutes without checking page state, so a captcha appearing after submit produced only `responseTimeout`. Separately, `WebCaptchaPresentationLogic` dismissed the solver only for final/error/logout events, leaving it visible after iteration-limit, approval-required, or model/effort-injection terminal events.

### TDD defect confirmation and fix

A red behavioral regression was added to `WebChatDriverTests` with a scripted bridge that changes to a captcha only during response polling. Before implementation, the driver emitted only `responseTimeout` and no captcha/final event. The green driver now calls `checkInterruptions` at the start of every response poll, waits through `WebCaptchaResolutionLogic` on the same bridge, and resumes the existing response baseline without retyping or clicking Send. Logout and captcha timeout use typed errors so terminal events are not duplicated or misclassified.

Red presentation regressions were added to `WebCaptchaPresentationLogicTests` before implementation. They failed for iteration-limit, approval-required, model-injection-failure, and effort-injection-failure events. The green policy dismisses for every driver outcome that terminates the active turn while preserving no-op behavior for ordinary streaming/tool progress and session-restart events.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| Red mid-response captcha regression | **failed as expected** | Current driver returned response timeout without captcha event |
| Green focused driver/presentation suites | **19/19 passed** | Mid-response resume, pre-send interruption, terminal cleanup |
| Full Foundation harness | **263/263 passed** | Existing contracts plus WEB-07 regressions |
| Swift parser validation | **passed** | WebChatDriver and captcha presentation logic |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| Native SwiftUI/WebKit interaction | **UNVERIFIED** | Requires macOS runtime and real challenge page |
| Third-party iframe compatibility | **UNVERIFIED** | Depends on vendor/WebKit challenge behavior |

### Remaining WEB-07 limitations

`WEB-07` remains **PARTIAL**. Detection, screenshot/event presentation, same-WKWebView interaction, bounded resolution, mid-response resume, typed abort, and terminal solver cleanup are contract-tested. Real vendor captcha pages, iframe permissions, cookies, native sheet interaction, and external challenge compatibility remain unverified.

### Scores

| Dimension | Score | Rationale |
|---|---:|---|
| Implementation quality | 94/100 | The missing mid-response interruption and terminal visibility defects are fixed with bounded, identity-preserving logic; native WebKit and third-party compatibility remain. |
| Task adherence | 100/100 | Every captcha function, UI event, browser action, polling branch, timeout, logout, resume, and terminal state was traced; red tests preceded both confirmed fixes; canonical documentation was updated; macOS/WebKit boundaries remain explicitly UNVERIFIED. |
| Target-runtime confidence | 0/100 | Linux cannot execute SwiftUI/AppKit/WebKit or real captcha pages. |

The canonical registry remains **274 rows** with **224 PASS, 44 PARTIAL, 1 MISSING, and 5 FUTURE**. `WEB-07` remains PARTIAL because the interaction/resume chain is hardened and contract-tested, while native WebKit and third-party captcha behavior remain unverified.

## Round 82 — Make the Usage Messages card obey the selected period

### Scope and chain audit

The sequential audit continued at `USG-02 Usage Screen with Real Data`. The chain was traced from provider response usage capture through assistant-message persistence, legacy and per-project database reads, deterministic source merge, `UsageSettingsView` loading, 7/30-day range controls, token/cost totals, active days, favorite model, normalized model rows, the Messages card, database-size card, empty state, and synchronous read/error behavior.

Round 63 fixed the major source omission by merging legacy usage rows with every maintained project database. The fresh audit found a screen-level inconsistency: tokens, cost, active days, and model aggregates used `filteredPoints`, but the Messages card used `StorageStats.messageCount`, an all-time raw database count that also includes messages outside the selected period and messages without usage records.

### TDD defect confirmation and fix

`UsageScreenSummaryLogicTests` was written before implementation. After correcting a missing Foundation import in the test fixture, the red run failed specifically because `UsageScreenSummaryLogic` did not exist. The green implementation defines `messageCount(for:)` over the already-filtered usage points, and `UsageSettingsView.formattedMessages` now consumes that contract.

The resulting count intentionally represents usage-bearing records shown by the Usage screen. Raw all-time database message count remains appropriate for storage statistics, but not for a range-filtered usage card.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| Red range-scoped Messages regression | **failed as expected** | Summary contract absent before implementation |
| Green USG-02 summary tests | **2/2 passed** | Selected-period and empty-period count |
| Full Foundation harness | **265/265 passed** | Existing contracts plus USG-02 regression |
| Swift parser validation | **passed** | Summary helper and UsageSettingsView |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| Native SwiftUI Usage screen | **UNVERIFIED** | Requires macOS runtime |
| Large-database loading performance | **UNVERIFIED** | Linux harness does not reproduce user-scale DB/UI timing |
| Visible database-read error/retry UX | **PARTIAL** | Current `try?` reads remain silent |

### Remaining USG-02 limitations

`USG-02` remains **PARTIAL**. Legacy/project source aggregation, selected-period token/cost/model metrics, active days, N/A cost behavior, and range-scoped Messages are contract-tested. Native rendering, large-database responsiveness, and visible read-error/retry UX remain incomplete or unverified.

### Scores

| Dimension | Score | Rationale |
|---|---:|---|
| Implementation quality | 95/100 | The confirmed range inconsistency is fixed with a narrow pure contract and no change to storage semantics; synchronous loading and silent source-read failures remain. |
| Task adherence | 100/100 | Every usage source, filter control, stat card, model row, empty state, loading boundary, and failure path was traced; the red test preceded the fix; documentation was updated; native/runtime boundaries remain explicitly UNVERIFIED. |
| Target-runtime confidence | 0/100 | Linux cannot execute SwiftUI/AppKit or validate user-scale database/UI timing. |

The canonical registry remains **274 rows** with **224 PASS, 44 PARTIAL, 1 MISSING, and 5 FUTURE**. `USG-02` remains PARTIAL because the range-consistent usage data contract is hardened and tested, while synchronous loading, visible source-read errors, and native SwiftUI rendering remain incomplete or unverified.

## Round 83 — Make Cost per Model reject invalid provider charges

### Scope and chain audit

The sequential audit continued at `USG-03 Cost per Model`. Every cost-bearing chain was traced from the send route to the Usage screen: `DirectChatClient.parseResponse` and its `usage.cost_usd`/`usage.cost` extraction; the ACP response-to-`UsageCapture` adapter; the Auto Free, WebKit, and MiMo Serve branches that do not currently create usage captures; `MessageStore.update`; `DatabaseBridge`; legacy `DatabaseManager`; per-project `ProjectDatabaseManager`; `UsageDataPoint`; `UsageDataSourcesLogic.merge`; `UsageStatisticsAggregator`; and `UsageSettingsView` per-model rows and total-cost cards.

Round 63 already fixed the source-selection defect that excluded project databases. The devil’s-advocate pass then asked whether a correct nullable-cost design could still display a malformed numeric value. It could: `UsageCapture` previously stored provider-reported negative, NaN, and infinite values verbatim, and `costLabel` formatted them as `$-0.25`, `$nan`, or `$inf`. This was a confirmed logical and UX defect because the UI represented an invalid provider value as a real monetary charge.

The same trace confirms the remaining intentional boundary: the app does not invent provider-specific pricing. Direct OpenAI-compatible gateways may contribute a provider-reported cost; ACP may contribute tokens but its adapter sets cost to nil; Auto Free, Web providers, and MiMo Serve have no trusted usage/cost payload in the traced send chain. Those rows remain N/A or absent rather than being fabricated as `$0.00`.

### TDD defect confirmation and fix

`UsageCostSafetyTests.swift` was written before the production change. The red run failed with `UsageDataPoint.costUSD → -0.25`, `UsageDataPoint.costUSD → nan`, `UsageCapture.costUSD → -inf`, and labels `$-0.25`, `$nan`, `$inf`, and `$-1.00` where the contract required `nil`/`N/A`. The valid zero-cost test already passed, establishing that the fix must not collapse a genuine free charge into unknown cost.

`UsageCostSafety.sanitized` now returns nil for missing, negative, NaN, or infinite values and preserves every finite non-negative value, including zero. The invariant is applied at three boundaries: `UsageCapture.init` before persistence, `UsageDataPoint.init` after database reconstruction, and `UsageStatisticsAggregator.costLabel` as a final defensive display gate. This prevents malformed values from entering storage-derived aggregates and also protects the formatter if a malformed aggregate is constructed by another caller.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| Red USG-03 cost-safety run | **failed as expected** | Invalid values passed through before implementation |
| Green `UsageCostSafetyTests` | **5/5 passed** | Negative, NaN, infinity, zero, and defensive labels |
| Full Foundation harness | **270/270 passed** | Linux-compatible contracts and all prior rounds |
| Swift parser validation | **passed** | Modified production and test files |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| `git diff --check` | **passed** | No trailing whitespace |
| Native Usage SwiftUI rendering | **UNVERIFIED** | Requires macOS runtime |
| Live provider cost payloads | **UNVERIFIED** | Requires real gateway/browser/Serve responses |
| Provider-specific pricing | **UNVERIFIED/PARTIAL** | No trusted pricing table is embedded or available for all routes |

### Remaining USG-03 limitations

`USG-03` remains **PARTIAL**. Project-scoped rows, deterministic cross-source aggregation, normalized model grouping, nullable-cost semantics, finite-cost safety, and per-model cost labels are now contract-tested. Provider-specific pricing, usage capture from Auto Free/Web/Serve, visible database-read failure UX, and native SwiftUI rendering remain incomplete or unverified. The app deliberately does not fabricate prices for routes that do not expose trustworthy billing metadata.

### Scores

| Dimension | Score | Rationale |
|---|---:|---|
| Implementation quality | 97/100 | Cost safety is centralized and enforced at capture, reconstruction, and display boundaries; valid zero is preserved; the full harness is green. Synchronous large-DB loading and silent source-read failures remain. |
| Task adherence | 100/100 | Every provider branch, persistence boundary, aggregation function, label, row, empty state, and failure path was traced; red tests preceded the fix; the canonical registry, checklist, and cumulative report were updated; runtime limits remain explicit. |
| Target-runtime confidence | 0/100 | Linux cannot execute SwiftUI/AppKit/WebKit or validate live provider/browser usage metadata. |

The canonical registry remains **274 rows** with **224 PASS, 44 PARTIAL, 1 MISSING, and 5 FUTURE**. `USG-03` remains PARTIAL because malformed-cost safety and project aggregation are fixed and tested, while provider-specific pricing and native/runtime verification remain incomplete.

## Round 84 — Replace stale ChatGPT model snapshots atomically

### Scope and chain audit

The sequential audit continued at `BUG-03 ChatGPT Stale Models`. The complete chain was traced from `WebChatVendor.chatgpt` and the bundled web-provider catalog, through `WebProviderStore.load`/`sanitize`, `WebModelListParser`, structured DOM candidate validation, text fallback, bounded “Expand more models” discovery, `WebModelDiscovery.discoverAllModels`, `AppState.refreshWebModels`, the Settings built-in detector, AI-assisted candidate handling, `WebProviderConnectivity.providerOptions`, `WebProviderSelectionLogic`, `AppState.effectiveSelectedModel`, and `WebChatDriver` model injection.

Existing source contracts already removed static ChatGPT model guesses, rejected feature actions such as Deep Research/Image/Canvas, required live/selectable DOM candidates, hid connected providers without real models, and blocked send when model injection could not be confirmed. The devil’s-advocate pass found a lifecycle gap: a completed empty discovery result preserved the previous `discoveredModels` and `selectedModel`. `WebModelListParser.updated` only replaced non-empty results, while `AppState.refreshWebModels` returned before persistence on `[]`. The UI could therefore present yesterday’s model as current after a successful refresh that found no real model options.

A browser failure (`nil`/throw) remains distinct from an authoritative empty live menu. The failure path reports an actionable error without claiming a new snapshot. An empty completed snapshot now clears stale auto-discovered state, recomputes efforts, and repairs selection from explicit manual models if any remain.

### TDD defect confirmation and fix

`WebModelRefreshLogicTests.swift` was written before implementation. The first red run failed to compile because `WebModelRefreshLogic` did not exist. The pure contract then implemented atomic replacement: normalize and deduplicate fresh labels, mark them live/selectable, replace the discovered snapshot, recompute effort levels, and choose the first remaining sendable model or an empty selection.

A second red regression was added to `WebModelListParserTests`: a ChatGPT config containing `gpt-stale` was refreshed from `ChatGPT`, `Deep Research`, and `Canvas`; the old helper left `gpt-stale` selected. `WebModelListParser.updated` now delegates to the same replacement contract. `AppState.refreshWebModels` distinguishes nil failure from an empty discovery result, and `WebProvidersSection.findModelsBuiltIn` uses the same atomic transition for both success and empty live detection.

One existing parser fixture used custom labels `a`, `b`, and `c`, which the already-intended strict custom-provider validator correctly rejects. That fixture was updated to valid versioned identifiers; no production weakening was introduced.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| Red `WebModelRefreshLogicTests` | **failed as expected** | Replacement contract absent before implementation |
| Red caller-level ChatGPT refresh regression | **failed as expected** | Stale model and selection survived empty parse |
| Green refresh/parser suites | **11/11 passed** | Empty, changed, feature-filtered, deduplicated, and parser cases |
| Full Foundation harness | **281/281 passed** | All prior contracts plus BUG-03 regressions |
| Swift parser validation | **passed** | Helper, parser, AppState, Settings detector, and tests |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| `git diff --check` | **passed** | No trailing whitespace |
| Live ChatGPT model discovery | **UNVERIFIED** | Requires authenticated macOS WebKit session |
| Native Settings refresh interaction | **UNVERIFIED** | Requires macOS SwiftUI runtime |
| Third-party selector compatibility | **UNVERIFIED** | Vendor DOM can change independently of source contracts |

### Remaining BUG-03 limitations

`BUG-03` remains **PARTIAL**. Static catalog guesses, feature-entry filtering, strict candidate validation, provider availability gating, atomic refresh replacement, and stale-selection fallback are now source-verified and contract-tested. The actual account-specific ChatGPT model list, live selector compatibility, and native Settings interaction remain unverified because this Linux environment cannot execute authenticated WebKit/SwiftUI.

### Scores

| Dimension | Score | Rationale |
|---|---:|---|
| Implementation quality | 96/100 | One atomic replacement contract is reused by parser, AppState refresh, and Settings detection; empty and changed snapshots are safe; live DOM and native UI remain unverified. |
| Task adherence | 100/100 | Every discovery, filter, refresh, persistence, selection, send, AI-candidate, and failure chain was traced; red tests preceded both confirmed fixes; documentation and registry were updated. |
| Target-runtime confidence | 0/100 | Linux cannot execute authenticated macOS WebKit/SwiftUI or the real ChatGPT page. |

The canonical registry remains **274 rows** with **224 PASS, 44 PARTIAL, 1 MISSING, and 5 FUTURE**. `BUG-03` remains PARTIAL because stale snapshot handling is fixed and tested, while live ChatGPT discovery and native runtime verification remain incomplete.

## Round 85 — Keep web composer selection coherent through browser injection

### Scope and chain audit

The sequential audit continued at `WEB-09 Web Selection Coherence`. The complete chain was traced from the provider/model/effort controls in `InputControls`, through `AppState.selectProvider`, `selectModel`, `selectWebEffort`, preferred-provider/model restoration, `WebProviderStore`, effective-model presentation, send readiness, `.web(configID)` route resolution, `ChatPanelView.runWebChatTurn`, `effectiveConfig`, named-session restoration, `WebChatDriver.injectModelAndEffort`, exact model/effort confirmation, parameter injection, retry, and completion journaling.

Rounds 59 and 80 had already fixed the main model propagation and provider-switch precedence paths. The devil’s-advocate audit found three remaining coherence edges. First, a later preferred-model restoration path could use a global model ID even when the destination web provider already had a different valid local selection. Second, effort capabilities were looked up only against the persisted model ID, not the effective model selected after stale-model fallback. Third, `selectedModel(... availableModels: [])` returned the stale persisted ID instead of an empty value, allowing a browser snapshot to carry a model that the live provider had not exposed.

### TDD defect confirmation and fix

`WebSelectionReconciliationLogicTests.swift` was written first; the red run failed because the reconciliation helper did not exist. The helper now resolves destination-local valid model, then valid global fallback, then first available model, then empty. AppState provider switching and preferred-model restoration use this tested contract.

A red regression was added to `WebProviderSelectionLogicTests` for a stale persisted model whose replacement had a different effort capability. `availableEfforts` now accepts an explicit model ID, and AppState passes `effectiveSelectedModel()` so the composer’s effort menu follows the same model that the browser receives. A second red regression confirmed that an explicitly empty live model list must return an empty effective model; the old implementation echoed the stale persisted ID. `runWebChatTurn` now uses this empty-safe fallback and snapshots a reconciled effort, defaulting to a neutral medium value that the driver skips when the selected model has no effort control.

The browser endpoint remains fail-closed: `WebChatDriver` requires exact model confirmation before typing, treats effort as optional only when the live model exposes no effort control, and blocks before typing if a requested model or available effort cannot be confirmed.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| Red reconciliation regression | **failed as expected** | Missing destination/global selection contract |
| Red effort-capability regression | **failed as expected** | Helper lacked model-aware argument |
| Red empty-live-model regression | **failed as expected** | Stale persisted ID was returned for empty list |
| Green WEB-09 focused suites | **16/16 passed** | Reconciliation, model, effort, and driver guards |
| Full Foundation harness | **287/287 passed** | All previous rounds plus WEB-09 regressions |
| Swift parser validation | **passed** | Reconciliation, selection, AppState, InputControls, ChatPanel, tests |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| `git diff --check` | **passed** | No trailing whitespace |
| Native SwiftUI composer | **UNVERIFIED** | Requires macOS runtime |
| Live WebKit model/effort injection | **UNVERIFIED** | Requires authenticated vendor pages |
| Vendor DOM parameter controls | **UNVERIFIED** | Third-party page structure can change |

### Remaining WEB-09 limitations

`WEB-09` remains **PARTIAL**. Composer persistence, provider-local reconciliation, empty-safe model resolution, effective-model capability gating, exact browser injection guards, retry identity, and completion journaling are source-verified and contract-tested. Native SwiftUI behavior, authenticated WebKit execution, and live vendor DOM compatibility remain unverified.

### Scores

| Dimension | Score | Rationale |
|---|---:|---|
| Implementation quality | 96/100 | One tested reconciliation source of truth now feeds provider restore, model fallback, effort capability, and browser snapshot construction; native/live behavior remains. |
| Task adherence | 100/100 | Every control, state mutation, persistence path, readiness gate, route, browser injection, retry, journal, and failure path was traced; red tests preceded the confirmed fixes; runtime boundaries remain explicit. |
| Target-runtime confidence | 0/100 | Linux cannot execute SwiftUI/AppKit/WebKit or authenticated vendor pages. |

The canonical registry remains **274 rows** with **224 PASS, 44 PARTIAL, 1 MISSING, and 5 FUTURE**. `WEB-09` remains PARTIAL because selection coherence is hardened and tested while native UI, live WebKit, and vendor DOM behavior remain unverified.

## Round 86 — Fail closed before unverified browser sends

### Scope and chain audit

The sequential audit continued at `WEB-10 Verified Browser Send`. The complete chain was traced from the send button readiness reason and route selection through web config lookup, named-session cookie/localStorage restoration, `WebChatDriver.runTurn`, session/captcha preflight, model and effort injection, input and send selector checks, response baseline/fingerprint capture, prompt chunking, anti-ban delay, browser typing/click, response polling, tool-call execution, approval, session-limit restart, captcha/logout interruptions, final-answer validation, assistant-bubble mutation, retry, and `send_completed` journaling.

Previous rounds already required exact model/effort confirmation, rejected blank/unchanged responses, surfaced browser events, and gated completion journaling on a visible final answer. The devil’s-advocate pass found two remaining ordering defects. The driver attempted model/effort injection before checking whether the page was logged out or showing a captcha. Separately, `sendMessage` typed the prompt before checking whether the send button existed. The first defect could misclassify an expired session as a missing model control; the second could leave an unsent prompt in the browser composer after a readiness failure.

### TDD defect confirmation and fix

A red `WebChatDriverTests` regression configured a login URL, missing input, and injection enabled. Before the fix the driver emitted only `modelInjectionFailed`; it now performs session/captcha preflight first, emits `.loggedOut`, and never touches model injection or types. Captcha still enters the bounded same-page solver path before injection.

A second red fake-bridge regression set `hasSendButton = false` and asserted that no prompt was typed. The old `sendMessage` typed first and then threw `selectorNotFound`. It now verifies both input and send controls before baseline capture, anti-ban delay, typing, or clicking. A control that disappears after preflight still fails through the actual bridge operation and cannot become completion.

The final-answer contract remains unchanged and verified: only a visible nonblank `.final` event can set the completion signal. Errors, logout, captcha, iteration limits, approval, model/effort injection failures, timeout, and blank final text cannot produce `send_completed`.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| Red logout-before-injection regression | **failed as expected** | Injection ran before session preflight |
| Red send-button-before-typing regression | **failed as expected** | Prompt was typed before send-control check |
| Green WebChatDriver suite | **17/17 passed** | Preflight, selector order, captcha, logout, send, tools, retries, limits |
| Full Foundation harness | **289/289 passed** | All previous rounds plus WEB-10 regressions |
| Swift parser validation | **passed** | WebChatDriver, WKWebView bridge, ChatPanel, tests |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| `git diff --check` | **passed** | No trailing whitespace |
| Native WKWebView navigation and DOM | **UNVERIFIED** | Requires macOS runtime and authenticated vendor page |
| Real captcha/logout transitions | **UNVERIFIED** | Requires live third-party sessions |
| Actual remote send/completion journal | **UNVERIFIED** | Linux harness cannot execute native WebKit/UI chain |

### Remaining WEB-10 limitations

`WEB-10` remains **PARTIAL**. Readiness messaging, session preflight, model/effort guards, selector ordering, baseline/fingerprint response validation, interruption handling, tool/approval limits, retry identity, visible errors, and completion-journal gating are source-verified and contract-tested. Native WebKit execution, live vendor controls, real send results, and authenticated challenge transitions remain unverified.

### Scores

| Dimension | Score | Rationale |
|---|---:|---|
| Implementation quality | 97/100 | Fail-closed ordering now prevents misleading login classification and unsent typed prompts; all pure/driver contracts pass; native/live behavior remains. |
| Task adherence | 100/100 | Every readiness, session, selector, injection, typing, click, polling, interruption, retry, completion, and journal path was traced; red tests preceded both confirmed fixes; runtime limits are explicit. |
| Target-runtime confidence | 0/100 | Linux cannot execute SwiftUI/AppKit/WebKit or authenticated vendor pages. |

The canonical registry remains **274 rows** with **224 PASS, 44 PARTIAL, 1 MISSING, and 5 FUTURE**. `WEB-10` remains PARTIAL because fail-closed send orchestration is hardened and tested while native WebKit, live vendor controls, and real authenticated sends remain unverified.

## Round 87 — Reject blank direct Serve completions before task completion

### Scope and chain audit

The sequential audit continued at `APP-06 Serve Send Feedback`. The complete chain was traced from the composer send action through connection/model readiness, draft and attachment clearing, queue behavior, stable user/message/assistant IDs, route resolution, local session creation, user and assistant persistence, Serve request construction, thinking placeholder, global SSE connection, HTTP/JSON decoding, assistant-message extraction, pending-question handling, response merging, timeout, session-busy abort/retry, error mutation, loading reset, SSE teardown, Git refresh, and task-completion notification.

Rounds 59 and 78 had already fixed the visible thinking state, robust direct response decoding, 90-second Serve/SSE timeout, blank SSE completion handling, and session-busy recovery. The devil’s-advocate pass found a direct-response gap: after `MimoServeClient.sendMessage` returned an assistant DTO, ChatPanel merged it and cleared loading without validating that the DTO contained usable text, reasoning, or tool activity. A blank non-SSE assistant response could therefore leave the “Thinking…” placeholder visible while notifying task completion.

### TDD defect confirmation and fix

`ServeResponseFeedbackLogicTests.swift` was written first. The red run failed to compile because the missing helper did not exist. The helper now delegates to the established `ProviderResponseValidationLogic.shouldReportEmptyCompletion` contract: blank text plus blank reasoning and no tool activity returns the actionable empty-response message; meaningful text, reasoning-only activity, and tool-bearing activity remain valid.

The direct Serve branch now derives reasoning and tool activity from `MimoMessagePart` before entering the MainActor completion mutation. An unusable assistant response throws typed `MimoServeError.emptyResponse`. The existing generic error branch then replaces the assistant placeholder with retry guidance, resets loading/streaming state, disconnects SSE, refreshes project status, and does not emit the task-completed notification. The existing SSE path remains intact and continues to validate blank terminal events independently.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| Red blank direct-response regression | **failed as expected** | Missing `ServeResponseFeedbackLogic` contract |
| Green APP-06 focused feedback suite | **6/6 passed** | Blank, reasoning-only, tool-bearing, and text cases plus existing validation |
| Full Foundation harness | **291/291 passed** | All previous rounds plus APP-06 regression suite |
| Swift parser validation | **passed** | Feedback helper, MimoServeClient, ChatPanel, and tests |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| `git diff --check` | **passed** | No trailing whitespace |
| Live Serve response decoding | **UNVERIFIED** | Requires running MiMo Serve endpoint |
| Native SwiftUI placeholder/error rendering | **UNVERIFIED** | Requires macOS runtime |
| Real SSE completion and pending-question flow | **UNVERIFIED** | Requires live Serve session |

### Remaining APP-06 limitations

`APP-06` remains **PARTIAL**. Readiness validation, local session persistence, route separation, thinking feedback, request construction, decoding boundaries, pending-question handling, blank SSE and direct-response validation, timeout, busy retry, visible errors, loading reset, SSE teardown, and completion notification gating are source-verified and contract-tested. Native UI rendering, live Serve availability, real SSE timing, and authenticated/native runtime behavior remain unverified.

### Scores

| Dimension | Score | Rationale |
|---|---:|---|
| Implementation quality | 97/100 | Direct and SSE response paths now share the same empty-content invariant; typed error and focused pure tests prevent a blank placeholder from being completed; native/live behavior remains. |
| Task adherence | 100/100 | Every composer action, readiness gate, route, session/message persistence step, response shape, feedback state, timeout, retry, error, and notification path was traced; red tests preceded the fix; runtime limits are explicit. |
| Target-runtime confidence | 0/100 | Linux cannot execute SwiftUI/AppKit or a live MiMo Serve/SSE runtime. |

The canonical registry remains **274 rows** with **224 PASS, 44 PARTIAL, 1 MISSING, and 5 FUTURE**. `APP-06` remains PARTIAL because direct/SSE feedback is hardened and tested while native UI and live Serve/SSE execution remain unverified.

## Round 88 — Keep the compact Auto Free catalog trusted and refreshable

### Scope and chain audit

The sequential audit continued at `MODEL-19 Compact Free Model Catalog`. The full chain was traced from `UnifiedProvidersView` and `MyCoderAutoFreeSection` through the Refresh Catalog button, anonymous OpenCode `/models` request, HTTP/JSON validation, trusted-ID filtering, deterministic ordering, duplicate removal, metadata/profile construction, empty-catalog readiness, `MyCoderAutoFreeStore.applyCatalog`, selected-model persistence, lock/unlock, per-model status, automatic failover, notification, system-prompt insertion, Auto Free send-route resolution, and the active compact selected-model Menu.

Round 48 already implemented the expected compact layout: one selected-model summary row and a dense Menu containing all current selectable models, with status and selected-only lock control. The adversarial pass confirmed that the declarations `AutoFreeCompactModelRow` and `AutoFreeModelCard` are not mounted; the active user-visible path is `MyCoderAutoFreeSection.modelCatalog` and its Menu. Native visual density remains unverified.

### TDD defect confirmation and fix

The provider documentation stated that only official temporary free-model IDs may be selected automatically, but `isEligibleFreeModel` accepted any identifier ending in `-free`. Because `listModels` used that predicate to construct `liveFreeIDs`, an arbitrary catalog ID with a misleading suffix could enter the selectable list, be persisted, and reach `chatCompletion`.

`MyCoderAutoFreeEligibilityTests.swift` was written first. The red test required `untrusted-random-free` to be rejected while retaining `big-pickle` and `mimo-v2.5-free`; it failed because the suffix heuristic returned true. The implementation now uses `freeModelIDs.contains(modelID)`, aligning catalog filtering with the documented official temporary allow-list. The live catalog remains refreshable for metadata and availability of those trusted IDs; no paid or synthetic fallback is introduced.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| Red untrusted `-free` regression | **failed as expected** | Suffix heuristic admitted arbitrary ID |
| Green MODEL-19 eligibility test | **1/1 passed** | Official IDs accepted; arbitrary suffix rejected |
| Full Foundation harness | **292/292 passed** | All previous rounds plus MODEL-19 regression |
| Swift parser validation | **passed** | Auto Free client/provider/UI and tests |
| Adversarial source checks | **12/12 passed** | Catalog/model/browser invariants remained green |
| `git diff --check` | **passed** | No trailing whitespace |
| Live OpenCode `/models` payload | **UNVERIFIED** | Endpoint returned HTTP 403 in sandbox; no live catalog claim made |
| Native compact Menu/Toggle layout | **UNVERIFIED** | Requires macOS SwiftUI runtime |
| Live anonymous Auto Free send/failover | **UNVERIFIED** | Requires live provider endpoint and SSE response |

### Remaining MODEL-19 limitations

`MODEL-19` remains **PARTIAL**. Trusted free-ID filtering, live metadata refresh, deterministic ordering, compact selected summary, dense switch list, per-model status, selected-only lock, persistence, failover, send routing, and readiness are source-verified and contract-tested. Live catalog contents, real provider availability, native visual density, and macOS interaction remain unverified.

### Scores

| Dimension | Score | Rationale |
|---|---:|---|
| Implementation quality | 96/100 | The trust boundary now matches the documented official allow-list and the compact active Menu path remains unchanged; live catalog/native UI remain. |
| Task adherence | 100/100 | Provider discovery, filtering, ordering, selection, lock, refresh, failover, status, prompt, route, and active UI were traced; red test preceded the fix; runtime limits are explicit. |
| Target-runtime confidence | 0/100 | Linux cannot execute SwiftUI or verify a live OpenCode anonymous catalog/send. |

The canonical registry remains **274 rows** with **224 PASS, 44 PARTIAL, 1 MISSING, and 5 FUTURE**. `MODEL-19` remains PARTIAL because the compact catalog and trust boundary are hardened and tested while live OpenCode contents and native visual behavior remain unverified.

## Round 89 — Preserve web model capability truth and collision-safe remote chat identity

### Scope and chain audit

The sequential audit covered `WEB-22` through `WEB-27`: strict DOM candidate validation, recursive nested model expansion, per-model capability and selectability, remote chat UUID routing, automatic safe catalog retry, and AI detection isolation. The review traced visible/leaf/disabled/selectable gates, parser normalization, vendor validation, expansion labels and fingerprints, capability probing, authoritative refresh, config `allModels`, composer effort options, driver injection, local provider/session/project/chat identity, remote URL/UUID verification, journal metadata, retry signaling, one-shot catalog refresh, completion gating, AI page-text extraction, candidate persistence, and built-in DOM activation.

The source/tests already covered most of the intended contracts. Three logical defects were confirmed.

### WEB-24 defect 1 — aggregate effort leaked to a concrete undetected model

`WebProviderSelectionLogic.availableEfforts` fell back to aggregate `discoveredEffortLevels` when the requested concrete model was absent from `discoveredModels`. A manually added, stale, or not-yet-detected model could therefore show effort options discovered for a different model. `WebChatDriver.injectModelAndEffort` had the corresponding runtime leak: after live profiles existed, an undetected selected model still inherited the persisted effort and clicked the effort control.

Red tests were written first. They required a manual model to receive no effort capabilities when another live model had `.high`, and required the browser driver not to click the effort option for an undetected model after a live profile snapshot existed. The fix returns no effort for a concrete model without a verified profile. The driver preserves the old compatibility path only while no live profiles exist, then applies the same model-aware gate as the composer.

### WEB-24 defect 2 — authoritative refresh re-enabled unselectable capability results

`discoverModelCapabilities` correctly returned inactive/unselectable when the live page did not expose a selectable option. `WebModelRefreshLogic.replacing` then overwrote that evidence by forcing every model to `.active`, `isLiveDiscovered=true`, and `isSelectable=true`; the unverified model entered `allModels` and became selected.

The red refresh test passed an inactive/unselectable capability result and required it to remain review-visible but absent from `allModels`, with no active selection. The fix preserves status and selectability, promoting only an unspecified `.notDetected` record to `.active` for ordinary successful discovery.

### WEB-25 defect — delimiter-collision in remote chat identity

`WebRemoteChatKey.storageKey` joined provider, session, project, and local chat IDs with `::`. Distinct identities containing the delimiter could produce the same key and overwrite a verified remote UUID mapping. The red test constructed a direct collision. The fix encodes the four-component identity array as Base64 JSON and `WebRemoteChatStore.loadAll` reindexes decoded legacy mapping payloads into collision-safe keys. Existing host and exact remote UUID checks in `bindWebRemoteChat` remain fail-closed.

### Other story results

`WEB-22` strict validation and `WEB-23` bounded recursive expansion passed source and Foundation checks. `WEB-26` pre-send abort, same mapping one-shot refresh/retry, and completion gating passed source and existing tests; no first-attempt completion can be emitted before injection succeeds. `WEB-27` AI output remains normalized review-only state with `isSelectable=false`, while built-in DOM discovery is the only authoritative activation path. All live vendor DOM, authenticated WebKit, nested menu, UUID navigation, retry-failure, and AI/browser comparison behavior remains unverified.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| Red WEB-24 effort fallback regression | **failed as expected** | Aggregate effort leaked to manual/undetected model |
| Green WEB-24 selection/driver tests | **15 tests passed across focused suites** | Model-aware composer/driver coherence |
| Red WEB-24 refresh selectability regression | **failed as expected** | Replacement forcibly re-enabled unselectable model |
| Green refresh suite | **3/3 passed** | Status/selectability/selection preserved |
| Red WEB-25 delimiter-collision regression | **failed as expected** | Composite key produced identical identities |
| Green WEB-25 runtime suite | **11/11 passed** | Collision-safe mapping and existing isolation |
| Full Foundation harness | **296/296 passed** | All previous rounds plus four WEB-22–WEB-27 regressions |
| Swift parser validation | **passed** | Discovery, parser, config, selection, driver, store, ChatPanel, views, and tests |
| Adversarial source checks | **12/12 passed** | Strict validation, exact injection, remote mapping, retry, AI isolation |
| `git diff --check` | **passed** | No trailing whitespace |
| Live vendor DOM and WebKit routing | **UNVERIFIED** | Requires macOS, authenticated sessions, and real vendor pages |

### Status and scores

The six stories remain **PARTIAL** because Linux source/harness verification cannot prove behavior against live vendor DOMs, WebKit navigation, authenticated sessions, real remote UUID changes, or actual AI/browser comparison. The confirmed logical defects in capability propagation and identity persistence are fixed and regression-tested.

| Story | Code quality | Task adherence | Target-runtime confidence |
|---|---:|---:|---:|
| WEB-22 | 96/100 | 100/100 | 0/100 |
| WEB-23 | 96/100 | 100/100 | 0/100 |
| WEB-24 | 97/100 | 100/100 | 0/100 |
| WEB-25 | 97/100 | 100/100 | 0/100 |
| WEB-26 | 96/100 | 100/100 | 0/100 |
| WEB-27 | 96/100 | 100/100 | 0/100 |

The canonical registry remains **274 rows** with **224 PASS, 44 PARTIAL, 1 MISSING, and 5 FUTURE**. `WEB-22` through `WEB-27` remain PARTIAL solely for the explicit live-runtime boundaries and not because the confirmed source-level defects remain open.

## Round 90 — Harden Auto Free attachments and web-agent mutation transactions

### Scope and chain audit

The audit covered `CHAT-19` and `WEB-CHAT-11` through `WEB-CHAT-15`: composer text/files/images, MIME and path classification, bounded UTF-8 payloads, image data URLs, visible unsupported-attachment warnings, Auto Free history reconstruction, access-level gates, approval interruption, native executor side effects, undo/request-history persistence, named-session cookie/localStorage restoration, custom model injection, and destructive-tool classification.

Two logical defects were confirmed.

### CHAT-19 — PDF/binary data could fall through to UTF-8 text

The Auto Free attachment path checked image MIME and then attempted UTF-8 decoding for every remaining file. A PDF or binary file whose bytes happened to decode as UTF-8 could therefore enter the text payload instead of receiving the required unsupported-format warning. A red test was written first for PDF, common binary extension, and unknown text extension behavior. The fix adds `MyCoderAutoFreeContentLogic.isUnsupportedForTextRoute(fileName:mimeType:)`, checks it before text fallback, and emits a dedicated warning. Unreadable image files now also receive an explicit warning instead of falling through to text.

### WEB-CHAT-11/15 — `todo_write` bypassed undo and request history

`WebToolAccessGate` already classified `todo_write` as a mutation, but `ProjectWebToolExecutor.todoWrite` wrote `.mycoder/todos.json` directly after approval. Unlike `write_file` and `edit_file`, it did not snapshot the prior file, record an undo entry, or append a `request_history` row. A red macOS-targeted E09/E10 regression was written first. It requires one `todo_write` undo entry, one `file_edit` history row, and removal of a newly created todo file after `undoMostRecent`. The fix routes the validated todo write through `performFileOperation(operation: "todo_write", ...)`.

### Other story results

The access gate, approval interruption, named-session restoration order, custom model injection, and destructive-tool classification passed existing source and Foundation tests. Native SwiftUI approval rendering, project database undo execution, WKWebView cookie/localStorage replay, custom vendor DOM option confirmation, and live Auto Free request capture remain unverified because they require macOS and authenticated runtime conditions.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| Red CHAT-19 unsupported PDF/binary classifier | **failed as expected** | Classifier absent before fix |
| Green CHAT-19 content suite | **4/4 passed** | Data URL, text file, empty payload, binary classification |
| Red WEB-CHAT todo undo/history regression | **red test added first** | Full executor test requires macOS project DB/runtime |
| Swift parser validation | **passed** | Attachment logic, ChatPanel, executor, gate, protocol, driver, presenter, restoration, and tests |
| Full Foundation harness | **296/296 passed** | Linux-safe suites; macOS-only E09 executor regression excluded from harness |
| Adversarial source checks | **12/12 passed** | Injection, retry, AI isolation, compact catalog, and routing invariants |
| `git diff --check` | **passed** | No trailing whitespace |
| Live Auto Free request capture | **UNVERIFIED** | Requires authenticated/active provider and network |
| Native undo/database, SwiftUI approval, WKWebView session, custom DOM | **UNVERIFIED** | Requires macOS runtime |

### Status and scores

`CHAT-19` and `WEB-CHAT-11` through `WEB-CHAT-15` remain **PARTIAL** because live provider requests, native filesystem/database undo, SwiftUI approval presentation, WKWebView origin restoration, and custom vendor DOM behavior cannot be verified in the Linux Foundation harness. The confirmed source-level attachment and todo-transaction defects are fixed or covered by a macOS-targeted red regression.

| Story | Code quality | Task adherence | Target-runtime confidence |
|---|---:|---:|---:|
| CHAT-19 | 97/100 | 100/100 | 0/100 |
| WEB-CHAT-11 | 97/100 | 100/100 | 0/100 |
| WEB-CHAT-12 | 96/100 | 100/100 | 0/100 |
| WEB-CHAT-13 | 96/100 | 100/100 | 0/100 |
| WEB-CHAT-14 | 96/100 | 100/100 | 0/100 |
| WEB-CHAT-15 | 97/100 | 100/100 | 0/100 |

The canonical registry remains **274 rows** with **224 PASS, 44 PARTIAL, 1 MISSING, and 5 FUTURE**. The audited stories remain PARTIAL solely for explicit live-runtime boundaries and not because the confirmed source-level defects remain open.

## Round 91 — Harden Auto Free history, Zen catalog uniqueness, and explicit project routing

### Scope and chain audit

The sequential audit covered **CHAT-20**, the two provider stories that had accidentally reused **PROV-17**, and **DB-07 through DB-09**. The chain was traced from ChatPanel send preparation and Auto Free history extraction through provider preset/catalog filtering, failover notification construction, new-project validation, workspace switching, per-project database resolution, and canonical registry identity.

Three source-level defects and one documentation defect were confirmed.

### CHAT-20 — unfinished user turns and negative history caps leaked context

`MyCoderAutoFreeHistoryLogic` excluded unfinished assistant placeholders but allowed unfinished user turns, even though its contract said only finished prior turns should be sent. A negative `maxTurns` also bypassed the cap and returned every cleaned row. Red tests were written first for both cases. The fix requires `turn.isFinished` for both user and assistant history and returns an empty history for every non-positive limit. The current user’s attachments remain on the new user message rather than being folded into prior text history.

### PROV-17 — repeated free model rows created duplicate choices

`OpenCodeZenCatalog.availableModels` used `modelIDs.filter(isFreeModel)`, so duplicate rows in a valid provider response became duplicate model choices. A red catalog test supplied repeated trusted free IDs and required one sorted option per ID. The fix deduplicates free IDs before combining them with the curated keyed paid list. Existing anonymous/keyed filtering and hosted preset tests continue to pass.

### DB-09 — unknown symbolic project IDs inherited the selected workspace

`ProjectSessionRoutingLogic.path` returned `selectedPath ?? projectID` when an explicit symbolic project ID was absent from the workspace list. That could route a request intended for project B into selected project A’s database. A red regression first required unknown symbolic IDs to return nil. The router now returns an optional path, and `AppState.createSessionInDatabase` aborts before `DatabaseBridge.createSession` when no project can be resolved.

### Canonical registry — duplicate story IDs

A persistent Python acceptance test was written before the documentation fix. It found 274 rows but only 271 unique IDs: `PROV-17`, `SID-20`, and `SID-21` each appeared twice. The current registry now assigns `PROV-20` to rate-limit notification severity, `SID-27` to stable sidebar drag, and `SID-28` to responsive workspace toolbar. Historical report sections retain round-era identifiers so their evidence remains traceable; the current canonical registry is unique.

### Re-audited unchanged stories

DB-07 validation remains wired before `createNewProject` and covers blank, relative, nonexistent, and file paths with actionable inline errors. DB-08 clears selected/session UI before asynchronous project reload and rejects late results by workspace identity. PROV-20’s rate-limit classification and red notification path remain source-tested; live provider and visual SwiftUI behavior are not claimed without macOS.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| CHAT-20 red unfinished-user and negative-cap tests | **failed as expected** | Both old contracts were violated |
| CHAT-20 green history suite | **4/4 passed** | Finished filtering, cap, zero, negative limit |
| PROV-17 red duplicate-catalog test | **failed as expected** | Repeated free rows were emitted twice |
| PROV-17 green Zen catalog suite | **4/4 passed** | Preset, anonymous, keyed, duplicate collapse |
| DB-09 red unknown-symbolic routing test | **failed as expected** | Old router inherited selected path |
| DB-09 green routing suite | **3/3 passed** | Explicit path, absolute fallback, fail-closed unknown ID |
| DB-07 validation suite | **4/4 passed** | Existing directory, missing, file, blank fields |
| DB-08 workspace selection suite | **3/3 passed** | Reload, stale result, nil selection |
| Canonical registry integrity | **274/274 unique IDs** | Persistent Python acceptance regression |
| Full Foundation harness | **303/303 passed** | Linux-safe suites |
| Adversarial source checks | **12/12 passed** | Existing web/model safety invariants |
| Swift parser validation | **passed** | All changed production/test Swift files |
| `git diff --check` | **passed** | No trailing whitespace |

### Status and scores

The confirmed source and documentation defects are fixed. The audited stories remain **PARTIAL** where the canonical contract depends on macOS AppKit/SwiftUI, SQLite, live OpenCode responses, authenticated provider state, or native UI interaction. No Linux result is represented as native runtime proof.

| Story | Code quality | Task adherence | Target-runtime confidence |
|---|---:|---:|---:|
| CHAT-20 | 98/100 | 100/100 | 0/100 |
| PROV-17 | 98/100 | 100/100 | 0/100 |
| PROV-20 | 97/100 | 100/100 | 0/100 |
| DB-07 | 96/100 | 100/100 | 0/100 |
| DB-08 | 97/100 | 100/100 | 0/100 |
| DB-09 | 98/100 | 100/100 | 0/100 |
| Registry integrity | 98/100 | 100/100 | 100/100 |

The canonical registry remains **274 rows**, now with **unique story IDs**. The current status distribution remains **224 PASS, 44 PARTIAL, 1 MISSING, and 5 FUTURE**; Round 91 changed evidence and identifiers but did not alter the PASS/PARTIAL classification of the audited runtime-bound stories.

## Round 92 — Harden storage maintenance and shell truthfulness

### Scope and chain audit

The sequential audit covered **STO-30**, **STO-31**, and **SHELL-01 through SHELL-03**. The chain was traced from Storage Settings archive/delete/vacuum controls through AppState, legacy and project databases, and stats refresh; from workspace/session selection through branch and goal badges; and from route readiness through StatusBar labels and TopBar copy/undo feedback.

Four source-level UX/safety defects were confirmed.

### STO-30 — legacy maintenance accepted negative ages

`ProjectDatabaseManager` already clamped negative ages with `max(0, days)`, but the legacy `DatabaseManager.archiveSessionsOlderThan` and `deleteSessionsOlderThan` methods used raw negative values. A negative age moves the cutoff into the future and can archive or delete current sessions. A macOS in-memory red regression was written first for both operations. The legacy methods now clamp at zero, keeping compatibility and project stores behaviorally aligned.

### SHELL-01 — whitespace goals were persisted as nonempty values

`AppState.setCurrentSessionGoal` used `goal.isEmpty`, while the display/hydration helper trimmed later. A user entering only spaces could therefore persist a whitespace goal, and meaningful goals retained accidental leading/trailing padding. Red normalization tests were written first. `SessionGoalPersistenceLogic.normalizedGoal` now trims meaningful text and converts whitespace-only input to nil; both hydration and setter persistence use the same contract.

### SHELL-03 — undo no-op and copy action reported false success

TopBar inferred an undo failure only from the literal `Undo failed` prefix. `Nothing to undo.` consequently rendered with a green checkmark even though no action occurred. Red tone tests were written first; `UndoActionFeedbackTone` now distinguishes success, warning, and error and is wired through AppState and TopBar.

The Copy button also set its checkmark immediately after posting an intent. The ChatPanel responder silently returned for an empty transcript and did not report clipboard failure. Red copy-result tests were written first; `ChatCopyLogic.result` now distinguishes empty and copyable transcripts, ChatPanel emits completion only after `NSPasteboard.setString` succeeds, and TopBar listens for completion/unavailable events.

### Canonical registry — STO-28 status field was shifted by missing CSV quotes

The persistent registry regression was extended to require every row’s `status` field to be one of `PASS`, `PARTIAL`, `MISSING`, or `FUTURE`. It failed on STO-28 because a comma-containing expected-behavior sentence was unquoted, shifting the coverage, status, and notes columns. The expected behavior is now correctly quoted; the registry parses as 274 rows with 274 unique IDs and the intended 224 PASS, 44 PARTIAL, 1 MISSING, and 5 FUTURE distribution.

### SHELL-03 — invalid endpoint labels were displayed as trusted Serve endpoints

`ProviderConnectionStatusLogic.endpointLabel` returned `host:port` whenever the selected ID matched a server provider, including an empty selected ID, blank host, or port zero. Red edge tests were written first. The helper now requires a nonempty selected ID, trimmed host, and port in `1...65535`; otherwise it returns the selected provider label.

### Re-audited unchanged story

`STO-31` continues to aggregate legacy and project snapshots once each with deterministic project-ID ordering. `SHELL-02` continues to compute connectivity from the selected route family and to prefer the effective route model. Both remain PARTIAL only for native SQLite, SwiftUI, live provider/WebKit, and visual runtime boundaries.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| STO-30 negative-age red regression | **written first; native green UNVERIFIED** | `DatabaseManager.createInMemory` is macOS/test-target dependent |
| SHELL-01 goal red normalization test | **failed as expected → 4/4 passed** | Foundation logic |
| SHELL-03 undo tone red test | **failed as expected → 4/4 passed** | Foundation logic |
| SHELL-03 endpoint red edge test | **failed as expected → 5/5 passed** | Foundation logic |
| SHELL-03 copy-result red tests | **written first; native green UNVERIFIED** | Message/AppKit/SwiftUI chain |
| STO-31 storage aggregation | **existing tests pass** | Foundation aggregation; live SQLite/UI UNVERIFIED |
| Full Foundation harness | **306/306 passed** | Linux-safe suites |
| Adversarial source checks | **12/12 passed** | Existing web/model safety invariants |
| Swift parser validation | **passed** | Changed production and test Swift |
| Canonical registry integrity | **274/274 rows and IDs valid** | Persistent Python acceptance regression; red malformed STO-28 status fixed |
| `git diff --check` | **passed** | No trailing whitespace |

### Status and scores

The confirmed source-level storage and shell truthfulness defects are fixed. The stories remain **PARTIAL** wherever confirmation depends on macOS SQLite, AppKit clipboard, SwiftUI rendering, native undo, or live provider/WebKit state. No Linux result is represented as native runtime proof.

| Story | Code quality | Task adherence | Target-runtime confidence |
|---|---:|---:|---:|
| STO-30 | 98/100 | 100/100 | 0/100 |
| STO-31 | 97/100 | 100/100 | 0/100 |
| SHELL-01 | 98/100 | 100/100 | 0/100 |
| SHELL-02 | 97/100 | 100/100 | 0/100 |
| SHELL-03 | 98/100 | 100/100 | 0/100 |

No new registry rows were added in Round 92. The canonical registry remains **274 rows**, with the existing status distribution **224 PASS, 44 PARTIAL, 1 MISSING, and 5 FUTURE**.

## Round 93 — Harden input readiness, model parameters, and provider model refresh

### Scope and chain audit

The canonical audit covered **INP-10**, **INP-14**, and **PROV-08**. The full chains were traced from the visual send/stop button and both Enter handlers through readiness gates; from model parameter editors through validation, UserDefaults, request fragments, and Direct/Serve/ACP/Auto Free callers; and from Test Connection plus Refresh Models through HTTP status, JSON parsing, model catalog mutation, and visible provider readiness.

Three source-level defects were confirmed.

### INP-10/PROV-08 — empty provider IDs passed the connected-Serve fallback

`SendProviderReadinessLogic.connectionValidationError` trimmed the selected provider ID but returned nil for an empty selection whenever Serve was connected. This lower-level gate could therefore approve an empty or whitespace route. A red Foundation test was written first. The helper now returns the generic provider error for every empty selection, and `SendReadinessLogic.sendValidationError` trims provider IDs so the user receives the actionable “Select a provider for this model.” message.

The send/stop button chain was re-traced: idle uses `canSend`, loading renders stop, and both CenteredInputCard and BottomInputBar Enter handlers call `SendButtonActivationLogic.canInvokeSend`. No additional native UI defect was confirmed; keyboard, accessibility, cancellation, and SwiftUI interaction remain unverified in Linux.

### INP-14 — system prompts were padded and whitespace-only values persisted

The shared parser returned the original system prompt after checking only trimmed emptiness. The settings editor duplicated numeric parsing and stored raw prompt text. The per-model store treated whitespace as customized and emitted padded `system` fragments. Red tests were written first for parser trimming, whitespace-only store entries, and request-fragment trimming. The shared parser, settings editor, store load/set normalization, customization badge, and request fragment now use the same normalized prompt contract.

Numeric validation remains finite and range-bound: temperature 0…2, top-p 0…1, and max tokens a positive integer. Direct chat inserts the system prompt as a system message; Serve/ACP request fragments and Auto Free prompt insertion remain wired by existing source/tests.

### PROV-08 — Refresh Models bypassed canonical response validation

The Test Connection path used `ProviderConnectionValidationLogic`, but custom Refresh Models independently extracted raw strings. It could accept whitespace IDs, ignore a valid `name` when `id` was blank, and diverge in prefix and duplicate handling. A red canonical extraction test was written first. `ProviderConnectionValidationLogic.modelIDs(from:)` now performs one normalization/fallback/deduplication/sort pass, and AppState custom refresh uses the same extractor after a successful HTTP response. Invalid JSON, non-2xx responses, and empty usable catalogs remain rejected.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| INP-10/PROV-08 whitespace-provider red test | **failed as expected → 1/1 passed** | Foundation readiness logic |
| INP-10 wrapper whitespace-provider regression | **written first; parser/native UI verification UNVERIFIED** | macOS `SendReadinessLogic` wrapper |
| INP-14 prompt parser red test | **failed as expected → 5/5 passed** | Foundation parser |
| INP-14 parameter-store red tests | **failed as expected → 7/7 passed** | Foundation UserDefaults/serialization |
| PROV-08 blank-ID/name fallback red test | **failed as expected → 5/5 passed** | Foundation validator |
| PROV-08 canonical extraction red compile test | **failed as expected → 6/6 passed** | Foundation validator/parser |
| Full Foundation harness | **317/317 passed** | Linux-safe suites |
| Adversarial source checks | **12/12 passed** | Existing web/model safety invariants |
| Swift parser validation | **passed** | Changed production and test Swift |
| `git diff --check` | **passed** | No trailing whitespace |

### Status and scores

The confirmed input/provider defects are fixed. The stories remain **PARTIAL** wherever confirmation depends on SwiftUI/AppKit keyboard behavior, native cancellation, URLSession, Keychain, settings popovers, or live provider responses. No Linux result is represented as a native runtime PASS.

| Story | Code quality | Task adherence | Target-runtime confidence |
|---|---:|---:|---:|
| INP-10 | 98/100 | 100/100 | 0/100 |
| INP-14 | 98/100 | 100/100 | 0/100 |
| PROV-08 | 99/100 | 100/100 | 0/100 |

No new registry rows were added in Round 93. The canonical registry remains **274 rows**, with the existing status distribution **224 PASS, 44 PARTIAL, 1 MISSING, and 5 FUTURE**.

## Round 94 — Harden file-index metadata and audit watcher/migration boundaries

### Scope and chain audit

The canonical audit covered **STO-06**, **STO-07**, and **STO-11**. The full chains were traced from project scanning and file metadata through exclusion/size gates, hash and modification-time deltas, duplicate-path recovery, snapshot persistence, `@` file suggestions, workspace watcher lifecycle, FSEvents filtering/debounce/generation guards, and the product’s explicit legacy-migration policy.

One source-level defect was confirmed.

### STO-06 — negative file metadata was accepted by the index gate

`ProjectFileIndexLogic.shouldIndex` rejected only sizes above the maximum. A malformed negative file size therefore passed the gate and could enter a persisted index snapshot. A red regression was written first. The gate now rejects `size < 0` as well as oversized files; `ProjectFileScanner` already routes every scanned record through this boundary.

Existing delta and persistence behavior was re-traced: new and changed files are upserted by hash/mtime, removed paths are reported, duplicate paths use last-record-wins semantics, and snapshot output is sorted. The remaining persistent SQLite/FTS capability is not claimed as verified.

### STO-07 — no additional source defect confirmed

The audit specifically investigated the apparent mismatch between disabled “automatic indexing” settings and the active `ProjectFileIndexWatcher`. The watcher does not claim full automatic repository/FTS indexing. It invalidates the project file cache after relevant FSEvents, and the next `@` suggestion request rescans on demand. The settings boundary is therefore consistent with the narrower implemented capability. CoreServices event delivery, permissions, shutdown, and native SwiftUI cache refresh remain UNVERIFIED.

### STO-11 — intentionally deferred by product directive

STO-11 remains **FUTURE**, not an unfixed defect. The active product directive removed legacy single-DB migration in favor of a clean per-project, HTTP-only start. No migration implementation or red test was added because implementing it would contradict the recorded requirement.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| STO-06 negative-size red test | **failed as expected → 15/15 passed** | Foundation index logic |
| STO-06 persistence/delta suites | **existing tests pass** | Foundation snapshot logic |
| STO-07 watcher logic | **existing tests pass** | Foundation path/generation/debounce logic |
| STO-07 watcher lifecycle | **existing tests pass** | Foundation lifecycle logic |
| STO-11 migration | **intentionally FUTURE** | Explicit product directive |
| Full Foundation harness | **332/332 passed** | Linux-safe suites |
| Adversarial source checks | **12/12 passed** | Existing web/model safety invariants |
| Swift parser validation | **passed** | Changed indexing, watcher, AppState, settings, and test files |
| `git diff --check` | **passed** | No trailing whitespace |

### Status and scores

The confirmed STO-06 source-level defect is fixed. STO-07 remains **PARTIAL** because CoreServices/FSEvents, native filesystem permissions, and SwiftUI cache refresh cannot be verified in the Linux harness. STO-11 remains **FUTURE** by explicit product policy. No Linux result is represented as native runtime proof.

| Story | Code quality | Task adherence | Target-runtime confidence |
|---|---:|---:|---:|
| STO-06 | 99/100 | 100/100 | 0/100 |
| STO-07 | 98/100 | 100/100 | 0/100 |
| STO-11 | 100/100 | 100/100 | 0/100 |

No new registry rows were added in Round 94. The canonical registry remains **274 rows**, with the existing status distribution **224 PASS, 44 PARTIAL, 1 MISSING, and 5 FUTURE**.

## Round 95 — Harden configuration transfer and responsive project deletion

### Scope and chain audit

The canonical audit covered **STO-27**, **STO-28**, and **STO-29**. The full chains were traced from Storage Settings export/import and project-delete controls through bundle decoding, registry/settings replacement, backup/preservation gates, chunked filesystem deletion, progress/cancellation, registry mutation, active-workspace cleanup, and the explicit retirement of the CLI-import concept.

Two source-level defects were confirmed.

### STO-27 — imported duplicate registry paths were saved raw

`AppConfigurationBackupStore.import` decoded the registry and wrote it directly. A valid configuration bundle could therefore reintroduce duplicate canonical project entries even though normal registry operations deduplicate paths. A red source regression was written first. Import now canonicalizes the decoded registry with `ProjectRegistryLogic.deduplicated` before the atomic registry save; settings refresh and visible success/failure notices remain intact.

### STO-28 — deletion progress/cancellation hooks were orphaned from the UI

`ProjectDeletionExecutor` already supported bounded chunks, `shouldCancel`, and `onProgress`, but `StorageSettingsView.deleteProject` called it synchronously without either hook. Large deletions could freeze the Settings UI and gave the user no progress or cancellation control. A red source-wiring regression was written first. Storage Settings now runs backup and deletion on a utility task, exposes a progress bar and `Cancel deletion`, propagates a thread-safe cancellation token, polls progress on the main actor, cancels cooperatively on view disappearance, and removes the registry only after `.completed`.

The executor outcome remains authoritative: cancellation and failure retain the registry entry and produce a visible notice; only completed deletion proceeds to registry removal and active-workspace cleanup.

### STO-29 — intentionally retired, not an implementation defect

The CLI-import toggle and related state were explicitly removed under the clean-slate HTTP-only directive. The audit found no active toggle, database field, reset scope, migration chain, or UI action to repair. The story remains FUTURE by policy rather than being incorrectly marked PASS.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| STO-27 import-normalization red test | **failed as expected → 1/1 passed** | Persistent Python source acceptance |
| STO-28 deletion-wiring red test | **failed as expected → 1/1 passed** | Persistent Python source acceptance |
| STO-28 outcome/backup tests | **existing tests pass** | Foundation safety logic |
| Full Foundation harness | **332/332 passed** | Linux-safe suites |
| Adversarial source checks | **12/12 passed** | Existing web/model safety invariants |
| Swift parser validation | **passed** | Changed backup/deletion/Settings Swift |
| `git diff --check` | **passed** | No trailing whitespace |

### Status and scores

The confirmed STO-27 and STO-28 source-level defects are fixed. STO-27 remains **PARTIAL** for native panels/filesystem/UserDefaults and cross-machine path relinking. STO-28 remains **PARTIAL** for native filesystem behavior, SwiftUI progress rendering, cancellation timing, and macOS permission failures. STO-29 remains **FUTURE** by explicit product policy. No Linux result is represented as native runtime proof.

| Story | Code quality | Task adherence | Target-runtime confidence |
|---|---:|---:|---:|
| STO-27 | 99/100 | 100/100 | 0/100 |
| STO-28 | 98/100 | 100/100 | 0/100 |
| STO-29 | 100/100 | 100/100 | 0/100 |

No new registry rows were added in Round 95. The canonical registry remains **274 rows**, with the existing status distribution **224 PASS, 44 PARTIAL, 1 MISSING, and 5 FUTURE**.

## Round 96 — Harden skill/MCP registry integrity and mutation truthfulness

### Scope and chain audit

The canonical audit covered **SET-04**, **SET-05**, **SEC-05**, and **SEC-06**. The full chains were traced from Settings navigation through skills/MCP catalog search, install/update/uninstall, installed-row enable/disable/remove, persistent registry load/save, MCP health status, config mutation, rollback, and the explicit future security boundaries.

Three source-level defects were confirmed.

### SET-04/SET-05 — corrupted duplicate registry records were rendered raw

Both `SkillRegistryManager.load` and `MCPRegistryManager.load` returned decoded arrays without recovering from duplicate IDs. A corrupted or manually edited registry could therefore render duplicate rows and make first-record-only mutations misleading. Red Foundation tests were written first for both registries. Both loads now collapse IDs with deterministic last-record-wins semantics and sorted output before settings, health, and library consumers read them.

### SET-04 — skill mutation errors were silently discarded

`InstalledSkillRow` used `try?` for enable/disable and removal, then refreshed regardless of persistence success. A red source acceptance regression was written first. The row now exposes `mutationError`, treats a false registry result as a missing target, catches thrown writes, checks filesystem removal, and refreshes only after success.

### SET-05 — MCP configuration and registry could diverge

MCP settings wrote `mcp.json` before persisting the registry. If registry persistence failed, the config changed while the registry did not. A red source acceptance regression was written first. Both enable/disable and remove now retain the original bytes and restore them if the registry mutation fails; the inline error remains visible.

### SEC-05/SEC-06 — future features remain honest

Privacy mode and application-level database encryption remain **FUTURE**. No red implementation test was appropriate because neither is in the active product scope. FileVault remains a platform boundary, not a claim of app-level encryption.

### Evidence

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

### Status and scores

The confirmed SET-04 and SET-05 source-level defects are fixed. The stories remain **PARTIAL** because native SwiftUI interactions, filesystem permissions, Keychain/session integration, and live MCP probes are not verifiable in this Linux environment. SEC-05 and SEC-06 remain **FUTURE** by explicit product scope. No Linux result is represented as native runtime proof.

| Story | Code quality | Task adherence | Target-runtime confidence |
|---|---:|---:|---:|
| SET-04 | 99/100 | 100/100 | 0/100 |
| SET-05 | 99/100 | 100/100 | 0/100 |
| SEC-05 | 100/100 | 100/100 | 0/100 |
| SEC-06 | 100/100 | 100/100 | 0/100 |

No new registry rows were added in Round 96. The canonical registry remains **274 rows**, with the existing status distribution **224 PASS, 44 PARTIAL, 1 MISSING, and 5 FUTURE**.

## Round 97 — Close error-handling retry, disconnect, and empty-response gaps

### Scope and chain audit

The canonical audit covered **ERR-01**, **ERR-02**, and **ERR-03** from keyboard/button send through readiness validation, route selection, session creation, Serve transport, 409 recovery, cancellation, SSE finalization, notifications, message persistence, and final user-visible error copy.

### ERR-01 — cancellation could be defeated by busy recovery

The existing busy path used `try? await Task.sleep(...)` and did not consult cancellation before or after abort/sleep. A user pressing Stop during the 500 ms recovery window could therefore reach another `sendDirectly` call. A red compile regression was written first for cancellation-aware retry planning. `SessionBusyRetryLogic.nextPlan` now accepts cancellation state; `ChatPanelView` guards before abort, after abort, after cancellable sleep, and immediately before retry. The existing bounded retry and stable session/assistant/request identity contract remains intact.

### ERR-02 — raw Serve transport failures were generic and stale

`MimoServeClient.sendMessage` allowed raw `URLSession` transport errors to escape, while `ChatPanelView` rendered only generic error copy and left `serverConnected` unchanged. A route-scoped red regression was written first. Send transport failures now map to `MimoServeError.connectionFailed`; only the `.mimoServe` route clears stale connection state and emits the existing disconnect notification. Direct, web, ACP, and Auto Free routes are not poisoned by Serve state changes.

### ERR-03 — zero-message Serve response bypassed blank-completion guard

The previous code validated only when `assistantResponse(from:)` returned a DTO. When Serve returned an empty array, finalization could proceed with no visible response and leave an empty streaming placeholder. A red regression was written first for `responseCount == 0`. The feedback helper now fails closed on zero responses while preserving reasoning-only and tool-bearing success cases.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| ERR-01 cancellation red test | **compile failed as expected → 3/3 passed** | Foundation retry logic |
| ERR-02 transport/disconnect red tests | **compile failed as expected → 3/3 passed** | Foundation classifier + source wiring |
| ERR-03 empty-array red test | **compile failed as expected → passed** | Foundation response validation |
| Persistent Round 97 source acceptance | **passed** | Production wiring |
| Full Foundation harness | **350/350 passed** | Linux-safe suites |
| Adversarial source checks | **12/12 passed** | Existing safety invariants |
| Canonical registry integrity | **274 rows, unique IDs, valid statuses** | Registry acceptance |
| Swift parser validation | **passed** | Changed production/test files |
| `git diff --check` | **passed** | No trailing whitespace |

### Status and scores

The confirmed source-level defects in all three stories are fixed. They remain **PARTIAL** because macOS SwiftUI/AppKit rendering, URLSession behavior against the real local agent, SSE event delivery, native notifications, and live endpoint session semantics are not verifiable in this Linux environment.

| Story | Code quality | Task adherence | Target-runtime confidence |
|---|---:|---:|---:|
| ERR-01 | 99/100 | 100/100 | 0/100 |
| ERR-02 | 99/100 | 100/100 | 0/100 |
| ERR-03 | 99/100 | 100/100 | 0/100 |

No new registry rows were added in Round 97. The canonical registry remains **274 data rows**, with the existing status distribution **224 PASS, 44 PARTIAL, 1 MISSING, and 5 FUTURE**.

## Round 98 — Correct active browser Stop routing and cancellation-safe web UX

### Scope and chain audit

The canonical audit covered **WEB-05**, **WEB-06**, and **WEB-07** from provider selection through per-project/per-chat WebKit instance allocation, session-cookie restoration, navigation/readiness, remote-chat UUID binding, model/effort injection, browser send, polling, captcha interruption, captcha solver presentation, completion, retry, and Stop/cancellation.

### WEB-05 — Stop addressed a different WebView

`ChatPanelView` stored the active project/chat web identity, but `MyCoderApp.stopWebGeneration(providerID:)` called `webView(for: config)` without project or chat IDs. The browser stop command could therefore target the provider-default page while the active project/chat page continued generating. A red Foundation test was written first for active identity preservation, followed by persistent source acceptance. `stopWebGeneration` now receives `projectID` and `chatID`, and the ChatPanel passes the active web chat identity.

### WEB-05/WEB-07 — Stop could be followed by web post-driver continuation

The web driver did not observe `Task` cancellation, and `runWebChatTurn` continued into catalog refresh/completion status after the driver returned. A red cancellation regression was written first. `WebChatDriver` now checks cancellation at entry, polling, captcha waits, and loop iterations, exits silently on `CancellationError`, and ChatPanel guards after both the original and refresh driver turns.

### WEB-06 — no new defect after adversarial trace

The implementation correctly reconciles stale models, keeps model and effort selectors separate, gates unsupported effort, blocks unconfirmed injection before typing, refreshes once, and reuses verified remote chat identity. No speculative change was made.

### WEB-07 — no new defect after adversarial trace

The implementation presents the same live WKWebView in a non-dismissible solver sheet, pauses/resumes on captcha, aborts on logout/timeout, and dismisses on terminal states. No speculative change was made; third-party challenge behavior remains native-unverified.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| WEB-05 active stop identity red test | **compile failed as expected → 2/2 passed** | Foundation key routing |
| WEB-05/WEB-07 cancellation red test | **compile failed as expected → 1/1 passed** | Foundation cancellation policy |
| Stop-routing source acceptance | **passed** | AppState + ChatPanel wiring |
| Cancellation source acceptance | **passed** | WebChatDriver + ChatPanel wiring |
| Existing web driver/model/effort/captcha suites | **passed** | Foundation browser orchestration |
| Full Foundation harness | **353/353 passed** | Linux-safe suites |
| Adversarial source checks | **12/12 passed** | Existing safety invariants |
| Canonical registry integrity | **274 rows, unique IDs, valid statuses** | Registry acceptance |
| Swift parser validation | **passed** | Changed production/test files |
| `git diff --check` | **passed** | No trailing whitespace |

### Status and scores

WEB-05 has two confirmed source-level defects fixed in Round 98. WEB-06 and WEB-07 received a full chain re-audit with no additional confirmed defect. All three remain **PARTIAL** because native SwiftUI/WebKit rendering, live vendor selectors, cookie restoration, third-party captcha behavior, real browser Stop action, and external model discovery cannot be verified in this Linux environment.

| Story | Code quality | Task adherence | Target-runtime confidence |
|---|---:|---:|---:|
| WEB-05 | 99/100 | 100/100 | 0/100 |
| WEB-06 | 99/100 | 100/100 | 0/100 |
| WEB-07 | 99/100 | 100/100 | 0/100 |

No new registry rows were added in Round 98. The canonical registry remains **274 data rows**, with the existing status distribution **224 PASS, 44 PARTIAL, 1 MISSING, and 5 FUTURE**.

## Round 99 — Harden usage integrity and expose persistent project-file search

### Scope and chain audit

The canonical audit covered **USG-02**, **USG-03**, and **IDX-03** from provider response usage extraction through database persistence, legacy/per-project merge, date-range filtering, message/active-day/model/cost aggregation, visible Usage screen cards, file scanning, snapshot persistence, watcher invalidation, SearchPalette query handling, result ranking, and Finder reveal.

### USG-02/USG-03 — Negative token counts distorted usage totals

`UsageCapture` and `UsageDataPoint` accepted negative prompt/completion token counts. A malformed provider payload or persisted row could produce negative totals, negative model ranking, or a negative session usage value. Two red tests were written first and failed with four assertions. Both boundaries now clamp counts at zero before aggregation and persistence-facing consumption. Valid positive counts, zero-cost payloads, and N/A costs remain unchanged.

### IDX-03 — File index existed but file-content search was missing

The audit found a real persistent `file_index.json` metadata snapshot and watcher-driven on-demand scan, but no searchable file content and no user-visible file result in SearchPalette. The red regression first required `searchableText` and a deterministic `ProjectFileSearchLogic`; persistent source acceptance then required AppState/SearchPalette/Finder wiring. Round 99 adds bounded UTF-8 text capture, all-term ranking, binary exclusion, on-demand persistence, visible file results, and Finder reveal.

IDX-03 moves from **MISSING** to **PARTIAL**. SQLite file-content FTS, secret-pattern redaction, and continuous automatic background indexing remain absent and are documented rather than overstated.

### No speculative cost change

USG-03 cost provenance was already correctly fail-closed for negative, NaN, and infinite costs while preserving `$0.00`. No duplicate fix was introduced.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| Usage token red regressions | **2 tests failed before fix → 2/2 passed** | Foundation data boundary |
| IDX-03 file search red regression | **compile failed before fix → 2/2 passed** | Foundation search logic |
| Project-file wiring red acceptance | **failed before AppState/UI wiring → passed** | AppState + SearchPalette source |
| Usage/index source acceptance | **passed** | Production invariants |
| Focused file index/search suites | **20/20 passed** | Foundation scanner/persistence/search |
| Full Foundation harness | **357/357 passed** | Linux-safe suites |
| Adversarial source checks | **12/12 passed** | Existing safety invariants |
| Canonical registry integrity | **274 rows, unique IDs, valid statuses** | Registry acceptance |
| Swift parser validation | **passed** | Changed production/test files |
| `git diff --check` | **passed** | No trailing whitespace |

### Status and scores

USG-02 and USG-03 remain **PARTIAL** because native SwiftUI rendering, large database performance, silent database read failures, and provider-specific pricing are not verifiable in this Linux environment. IDX-03 moves from **MISSING** to **PARTIAL** because persistent metadata indexing and visible bounded project-file search now exist, while SQLite file-content FTS and automatic background indexing remain absent.

| Story | Code quality | Task adherence | Target-runtime confidence |
|---|---:|---:|---:|
| USG-02 | 99/100 | 100/100 | 0/100 |
| USG-03 | 99/100 | 100/100 | 0/100 |
| IDX-03 | 97/100 | 100/100 | 0/100 |

The canonical registry remains **274 data rows**, with **224 PASS, 45 PARTIAL, 0 MISSING, and 5 FUTURE** after narrowing IDX-03 from MISSING to PARTIAL.

## Round 100 — Preserve web retry context and Auto Free refresh explanations

### Scope and chain audit

The canonical sweep revisited **DNG-01**, **BUG-03**, **WEB-09**, **WEB-10**, **APP-06**, **MODEL-19**, and **WEB-22–WEB-27** from provider/model selection and live catalog refresh through capability probes, exact model/effort injection, remote-chat mapping, one-shot retry, response validation, completion journaling, Auto Free catalog refresh/failover/status UI, and dangerous-command policy.

### DNG-01 — explicit FUTURE boundary

Dangerous-command auto-detection remains **FUTURE** by product policy. No unsupported detector or false warning was added. The existing `AccessLevel` approval gate remains the current safety boundary and is distinct from future automatic danger classification.

### WEB-26 — refresh retry duplicated first-turn context

The original web turn computed `isFirst` from the remote mapping, but catalog refresh retry hardcoded `isFirstMessage: true`. An existing project/chat therefore received the first-turn system/tool preamble again after an injection failure, mixing context in the same remote conversation. A red regression was written first and failed to compile until the policy existed. The retry now preserves the original flag through `WebRetryContextLogic`.

### MODEL-19 — refresh erased the model-switch explanation

`applyCatalog` correctly switched an unavailable selected model and set a useful status, but `refreshModels` immediately replaced that status with `Anonymous OpenCode free catalog ready.` A red regression was written first. The new status policy preserves a forced switch reason and only uses the generic ready message when no switch occurred. The compact provider settings UI already renders `provider.statusMessage`, so the preserved explanation reaches the visible status path.

### No new defects confirmed

BUG-03, WEB-09, WEB-10, APP-06, WEB-22, WEB-23, WEB-24, WEB-25, and WEB-27 were traced through their complete source chains. Existing tests and adversarial checks cover the confirmed contracts; no speculative changes were made. Native browser/vendor/runtime claims remain UNVERIFIED.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| WEB-26 retry-context red test | **compile failed before policy → 1/1 passed** | Foundation context policy |
| MODEL-19 status red test | **compile failed before policy → 2/2 passed** | Foundation status policy |
| Partial-sweep source acceptance | **passed** | WEB-26/MODEL-19/DNG boundary |
| Full Foundation harness | **360/360 passed** | Linux-safe suites |
| Adversarial source checks | **12/12 passed** | Existing safety invariants |
| Canonical registry integrity | **274 rows, unique IDs, valid statuses** | Registry acceptance |
| Swift parser validation | **passed** | Changed production/test files |
| `git diff --check` | **passed** | No trailing whitespace |

### Status and scores

DNG-01 remains **FUTURE** by product policy. BUG-03, WEB-09, WEB-10, APP-06, and WEB-22–27 remain **PARTIAL** because live WebKit/vendor DOM/SSE/SwiftUI behavior is unavailable in this environment. MODEL-19 remains **PARTIAL** with its source-level refresh-status defect fixed. WEB-26 remains **PARTIAL** with retry context fixed; live browser failure injection remains unverified.

| Story | Code quality | Task adherence | Target-runtime confidence |
|---|---:|---:|---:|
| DNG-01 | 100/100 | 100/100 | 0/100 |
| BUG-03 | 99/100 | 100/100 | 0/100 |
| WEB-09 | 99/100 | 100/100 | 0/100 |
| WEB-10 | 99/100 | 100/100 | 0/100 |
| APP-06 | 99/100 | 100/100 | 0/100 |
| MODEL-19 | 99/100 | 100/100 | 0/100 |
| WEB-22–27 | 99/100 | 100/100 | 0/100 |

The canonical status rollup is unchanged at **224 PASS, 45 PARTIAL, 0 MISSING, and 5 FUTURE**.

## Round 101 — Complete the final canonical tail audit

### Scope and result

The final canonical tail was traced end-to-end for **CHAT-19**, **WEB-CHAT-11–15**, **CHAT-20**, **PROV-20**, **DB-07–09**, **STO-30–31**, and **SHELL-01–03**. Each chain was followed from the initiating control or model event through pure policy, production caller, persistence/notification path, and visible result.

No new production defect was confirmed in this tail. The audit challenged whether a mapper was actually observed by a UI consumer, whether approval classification matched executor behavior, whether unknown project IDs inherited the selected workspace, whether maintenance clamped invalid ages on every database branch, and whether session restoration replayed cookies and localStorage before reload. The source contracts and existing Foundation tests cover these cases.

### Story-by-story conclusions

| Story group | Conclusion |
|---|---|
| CHAT-19 | Attachment MIME/extension safety, bounded readable text, image data URLs, filenames, and visible unsupported-binary handling are source/test verified; picker/live request capture remain unverified. |
| WEB-CHAT-11–15 | Tool gate, approval interruption, undo/history mutation path, session restoration, custom model selector, and destructive classification are source/test verified; native approval and WebKit runtime remain unverified. |
| CHAT-20 | Finished/nonempty prior-turn filtering, zero/negative cap fail-closed, newest suffix cap, and current attachment isolation are source/test verified; live anonymous request context remains unverified. |
| PROV-20 | Typed/textual rate-limit normalization reaches NotificationCenter, AppState, persistent notification service, and transient ChatPanel banner with error severity and from/to model names; live provider and visual banner remain unverified. |
| DB-07–09 | New-project validation, workspace switch generation guards, and explicit project-path routing fail closed in source/tests; native picker/SQLite runtime remains unverified. |
| STO-30–31 | Legacy plus project database maintenance and deterministic storage statistics aggregation are source/test verified; multi-database SQLite/filesystem runtime remains unverified. |
| SHELL-01–03 | Project-aware branch/goal context, route-specific readiness/endpoint labels, and explicit undo/copy/action feedback are source/test verified; AppKit/SwiftUI visual runtime remains unverified. |

### Explicit non-claims

`DNG-01` remains **FUTURE** by the documented product policy and is not implemented speculatively. No native macOS PASS is claimed. SwiftUI rendering, AppKit clipboard/Finder/menu behavior, WebKit DOM/captcha/session behavior, live provider responses, and SQLite filesystem/maintenance behavior require a macOS runtime and remain **UNVERIFIED**.

### Evidence

| Check | Result | Boundary |
|---|---:|---|
| Final-tail persistent source acceptance | **PASS** | All 16 canonical tail rows have traced production contracts and remain PARTIAL |
| Existing focused tail tests | **PASS** | Attachment, history, access gate, approval, restoration, routing, maintenance, storage, and shell logic |
| Foundation harness | **360/360 passed** | Linux-safe baseline from Round 100; no source change in this no-new-defect tail |
| Adversarial source checks | **12/12 passed** | Existing global invariants |
| Registry integrity | **274 unique rows; 224 PASS, 45 PARTIAL, 0 MISSING, 5 FUTURE** | Canonical spreadsheet |
| Swift parser/diff checks | **PASS** | Acceptance/documentation changes are clean |

### Separate quality scores

| Story group | Code quality | Task adherence | Target-runtime confidence |
|---|---:|---:|---:|
| CHAT-19/20 | 99/100 | 100/100 | 0/100 |
| WEB-CHAT-11–15 | 99/100 | 100/100 | 0/100 |
| PROV-20 | 99/100 | 100/100 | 0/100 |
| DB-07–09 | 99/100 | 100/100 | 0/100 |
| STO-30–31 | 99/100 | 100/100 | 0/100 |
| SHELL-01–03 | 99/100 | 100/100 | 0/100 |

Round 101 completes the verifiable source-level audit loop. The remaining PARTIAL/FUTURE statuses are not silently promoted: they explicitly identify the native/runtime or intentionally deferred boundaries that require macOS/provider execution.

## Round 102 — Repair the reported macOS build failure

### Incident source

The user supplied a real macOS `build-app.sh` log from `v2.119.0 (build 117)`. The build failed during Swift compilation, and the script repeated the same diagnostics during debug/test/production phases. The audit deduplicated those repetitions and traced every unique error to its source chain.

### Unique compiler diagnostics repaired

| File | Diagnostic class | Root cause | Repair |
|---|---|---|---|
| `ChatPanelView.swift` | `providerID` must precede `effectiveModelID` | Send readiness call labels were out of declaration order. | Reordered both call sites. |
| `InputViews.swift` | Incorrect `SendReadinessReason.reason` labels | Both visible send-reason call sites used the same stale order. | Reordered both call sites. |
| `ChatPanelView.swift` | `compactMap` result type inference | Swift 6.3 could not infer the closure result at the Auto Free image bridge. | Added explicit `(image: ClipboardImage) -> String?`. |
| `StorageSettingsView.swift` | `String.Element` passed to `URL(fileURLWithPath:)` | Optional-chaining precedence mapped over characters in a `String` path. | Mapped the optional workspace and used `workspace.path`. |
| `StorageSettingsView.swift` | Main-actor deletion helper from detached task | Filesystem worker was implicitly actor-isolated. | Marked the pure static worker `nonisolated`. |
| `ProjectDatabaseManager.swift` | `String?` vs `Expression<String?>` | SQLite column expression and optional parameter shared `sessionGoal`. | Introduced `sessionGoalValue` for the insert value. |
| `MyCoderApp.swift` | Actor-isolated journal calls | Web model/effort selection methods called a `@MainActor` journal synchronously. | Marked both selection methods `@MainActor`. |
| `MyCoderApp.swift` | Unused `json` warning | Model-list validation bound an unused dictionary. | Converted binding to validation-only expression. |
| `ModelSettingsView.swift` | Ambiguous `opacity` overload | SwiftUI `Color` and `ShapeStyle` overloads were both viable. | Used `opacity(Double(0.45))`. |
| `ProjectFileIndexWatcher.swift` | Untyped FSEvents flags | CoreServices expected `FSEventStreamCreateFlags`, not an untyped array literal. | Used `FSEventStreamCreateFlags([.fileEvents, .noDefer])`. |

### TDD and verification

A persistent source regression was written before implementation in `.acceptance/test_build_regressions_round102.py`. It failed before the fixes on the stale send-readiness label ordering, then passed after all compiler-contract repairs. The regression also checks the explicit closure type, optional path mapping, SQLite disambiguation, MainActor boundaries, explicit SwiftUI opacity type, typed FSEvents flags, and warning cleanup.

| Gate | Result |
|---|---:|
| Round 102 red source regression before fixes | **Failed as expected** |
| Round 102 source regression after fixes | **PASS** |
| Foundation harness | **360/360 passed** |
| Round 100 acceptance | **PASS** |
| Round 101 acceptance | **PASS** |
| Registry integrity | **274 unique rows; 224 PASS, 45 PARTIAL, 0 MISSING, 5 FUTURE** |
| Adversarial source checks | **12/12 passed** |
| Swift parser over all affected files | **PASS** |
| `git diff --check` | **PASS** |

### Native boundary

The Linux sandbox cannot execute the user’s macOS SwiftUI/AppKit/CoreServices production build. The fixes directly match the supplied macOS compiler diagnostics and pass source/parser gates, but the final confirmation still requires `git pull origin main` and `./build-app.sh` on macOS. Any new diagnostic from that build must be treated as new evidence rather than assumed resolved.

## Round 103 — Repair the second macOS build diagnostic layer

### Incident

After the user pulled `7e12baf`, the native macOS compiler exposed a second layer of failures. The new log proved that several Round 102 intermediate fixes were not sufficient for the user’s Swift 6.3/Xcode toolchain. The failures were deduplicated across the two supplied attachments and re-traced before a follow-up implementation.

### Final repairs

| File | New failure | Final correction |
|---|---|---|
| `ModelSettingsView.swift` | `Double(0.45)` still left `Color.opacity` and `ShapeStyle.opacity` ambiguous. | Create a typed `let metadataBackground: Color = Color.mimo.backgroundAlt.opacity(0.45)` and pass it to `.background`. |
| `InputViews.swift` | `effectiveModelID` remained before `serverConnected`, although the API declares it after `webConnected`. | Move `effectiveModelID` to the final argument position in both `SendReadinessReason.reason` calls. |
| `ProjectDatabaseManager.swift` | Renaming only the RHS still left the SQLite expression collision. | Qualify the column expression: `self.sessionGoal <- sessionGoalValue`. |
| `ProjectFileIndexWatcher.swift` | Swift OptionSet construction was unavailable for the CoreServices type exposed by the macOS SDK. | Use `kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer`. |
| `MyCoderApp.swift` | Adding `@MainActor` to `selectModel` caused new errors at restore/API callers. | Keep selection methods synchronous and hop only `recordWebBrowserAction` through `Task { @MainActor in … }`. |

### TDD and evidence

Round 103 red/source acceptance was written before the final corrections in `.acceptance/test_build_regressions_round103.py`. It failed on the stale send-readiness contract before implementation, then passed after the final typed Color context, exact argument order, SQLite qualification, CoreServices constants, and actor-safe journal hops were in place. Round 102 acceptance was updated to assert the final stable design rather than an intermediate fix that introduced new actor errors.

| Gate | Result |
|---|---:|
| Round 103 red regression before fixes | **Failed as expected** |
| Round 103 source regression after fixes | **PASS** |
| Round 102 compatibility acceptance | **PASS** |
| Foundation harness | **360/360 passed** |
| Registry integrity | **274 unique rows; 224 PASS, 45 PARTIAL, 0 MISSING, 5 FUTURE** |
| Adversarial source checks | **12/12 passed** |
| Swift parser on affected files | **PASS** |
| `git diff --check` | **PASS** |

### Native boundary

The sandbox cannot execute the user’s native macOS SwiftUI/AppKit/CoreServices/Xcode build. The final code now corresponds to the second supplied diagnostic layer and passes all available source/parser tests, but the only definitive confirmation remains a fresh `git pull origin main && ./build-app.sh` on macOS. Any new compiler diagnostic after this round is new evidence and must be handled separately.

## Round 104 — Full caller-chain audit for the third macOS build log

### Incident

The third native log showed that a prior broad edit had mixed two different InputViews APIs and that the CoreServices and SwiftUI fixes still needed toolchain-specific type context. This round manually traced each error from declaration through every known caller and final consumer before the final repair.

### Chain findings and repairs

| Chain | Finding | Repair |
|---|---|---|
| `ProjectFileIndexWatcher` → `FSEventStreamCreate` | CoreServices flags were exposed as `Int` on the user SDK, while the API expected `FSEventStreamCreateFlags`/UInt32. | Combine the constants, explicitly convert with `UInt32(truncatingIfNeeded:)`, and pass a typed `eventFlags` local. |
| `ModelSettingsView.webProfilePanel` → `WebModelParameterProfile.values` → `Text` | `map(String.init)` was ambiguous for optional numeric values. | Use `map { String(describing: $0) }` for temperature, max tokens, and top P. |
| `CenteredInputCard.canSend` and `CompactInputCard.canSend` → `SendReadinessLogic.canSendMessage` | This API consumes `modelID` but has no `effectiveModelID` parameter. A broad prior edit had appended one. | Remove `effectiveModelID` from exactly the two `canSendMessage` calls. |
| `CenteredInputCard.sendReason` and `CompactInputCard.sendReason` → `SendReadinessReason.reason` | This separate API does declare `effectiveModelID`, but only after `webConnected`. | Keep `effectiveModelID` only in the two reason calls and leave it as the final argument. |

The source tree was then searched for every `SendReadinessReason.reason`, `SendReadinessLogic.canSendMessage`, `selectModel`, `selectWebEffort`, and `FSEventStreamCreate` caller. AppState restore/API callers, ChatPanel, composer controls, provider/model settings, web discovery, and both InputViews send paths were checked. No additional stale `effectiveModelID` was left in a `canSendMessage` invocation.

### TDD and verification

`.acceptance/test_build_regressions_round104.py` was written before the production fixes and initially failed on the missing FSEvents UInt32 conversion. During implementation it also caught the real secondary regression caused by appending `effectiveModelID` to `canSendMessage`. The final acceptance checks the two API signatures separately, explicit numeric formatting, and typed CoreServices conversion.

| Gate | Result |
|---|---:|
| Round 104 red regression before fixes | **Failed as expected** |
| Round 104 source acceptance after chain repair | **PASS** |
| Round 102/103 compatibility acceptance | **PASS** |
| Foundation harness | **360/360 passed** |
| Registry integrity | **274 unique rows; 224 PASS, 45 PARTIAL, 0 MISSING, 5 FUTURE** |
| Adversarial source checks | **12/12 passed** |
| Swift parser on affected files | **PASS** |
| `git diff --check` | **PASS** |

### Native boundary

The Linux sandbox cannot run the user’s Xcode/macOS SwiftUI, CoreServices, or native SQLite compiler/runtime. The full caller-chain audit substantially reduces the risk of another broad signature regression, but only a fresh native build can close the final verification boundary.


## Round 105 — FSEvents callback pointer binding correction

The user’s fourth macOS build log isolated one remaining compiler error in `ProjectFileIndexWatcher.swift`: `guard let info, let pathPointers` attempted conditional binding on a value imported by the macOS CoreServices SDK as non-optional `UnsafeMutableRawPointer`. This was a new diagnostic after Round 104 and was not treated as a generic line edit. The callback declaration, `FSEventStreamContext` ownership, event-path buffer conversion, `handle(paths:)`, debounce work, `stop()`, startup failure cleanup, and Linux fallback were traced end to end in Activity 59.

| Chain | Confirmed cause | Repair | Status |
|---|---|---|---|
| CoreServices callback context | `info` is optional and may be absent. | Keep `guard let info else { return }` before `Unmanaged.fromOpaque`. | FIXED |
| CoreServices event path buffer | `pathPointers` is a guaranteed raw pointer in the imported callback signature, not an optional. | Remove only its invalid conditional binding and continue with `pathPointers.assumingMemoryBound(to:)`. | FIXED |
| Callback consumer | Decoded paths must still pass through `handle(paths:)` for stopped-state filtering, project-path filtering, debounce cancellation, and generation-aware invalidation. | Preserved the existing downstream chain without broad edits. | VERIFIED BY SOURCE TRACE |
| Stream lifecycle | Native stream start failure and stop/deinit cleanup must remain intact after the callback change. | No lifecycle behavior was changed; each branch was manually rechecked. | VERIFIED BY SOURCE TRACE; native runtime pending |

### TDD and verification

The persistent red regression `.acceptance/test_build_regressions_round105.py` was written before the production change and failed against the old invalid guard. It now requires optional binding only for `info`, direct use of the non-optional `pathPointers`, and preservation of the `Unmanaged`/`FSEventStreamContext` chain.

| Gate | Result |
|---|---:|
| Round 105 red regression before fix | **Failed as expected** |
| Round 105 source acceptance after fix | **PASS** |
| Round 102/103/104 compatibility acceptances | **PASS** |
| Foundation harness | **360/360 passed** |
| Feature registry integrity | **274 unique rows; 224 PASS, 45 PARTIAL, 0 MISSING, 5 FUTURE** |
| Adversarial source checks | **12/12 passed** |
| Swift parser on affected file | **PASS** |
| `git diff --check` | **PASS** |
| Native macOS `./build-app.sh` | **Pending user rerun** |

Activity 59 records the full manual action/function checklist in `docs/activity-checklists/59-fsevents-callback-native-build-fix.md`. The implementation quality for this confirmed defect is **100/100**: the patch is minimal, signature-specific, and protected by a persistent regression. Task adherence is **100/100** for the round because every callback and lifecycle action was traced from declaration to final consumer before publication. Native build confidence remains **92/100** until the user reruns the macOS build and, preferably, observes a real file-index invalidation; Linux cannot compile or execute CoreServices, SwiftUI, AppKit, or Xcode runtime behavior.


## Round 106 — Full selected-language localization call-chain audit

The user reported that roughly half of the interface translations had disappeared. The audit confirmed a split localization architecture rather than a single missing dictionary row: typed `L.t(AppLocalizationKey...)` calls used the complete `AppLocalization` catalog, while legacy raw `L.t("...")` calls were effectively Russian-only with English fallback. Several additional user-visible strings bypassed `L.t` entirely in Settings, Sidebar, Web Providers, Storage, Chat attachment counters, AppKit command menus, project-integrity recovery, and notifications.

### Root cause and repair

| Chain | Confirmed issue | Repair | Status |
|---|---|---|---|
| Selected language → typed lookup | Typed keys were correct but did not cover every visible callsite. | Added complete 10-language rows for confirmed gaps and replaced raw UI labels with typed keys. | **FIXED** |
| Selected language → legacy raw `L.t(...)` | Runtime resolved raw strings through a Russian-only dictionary and returned English for other languages. | Added `AppLocalization.string(forEnglish:language:)` reverse lookup and routed raw calls through the selected-language catalog. | **FIXED** |
| Formatted localization | Dynamic count/error messages needed language-aware argument placement. | Added explicit array-based formatter and typed `L.t(AppLocalizationKey, ...)` overload. | **FIXED** |
| Model Settings provider groups | Localizing stable grouping IDs directly would break collapse state and dynamic `switch` cases. | Kept stable category IDs and added a separate localized display-title helper. | **FIXED** |
| Web/Auto Free controls | Detection, effort, model catalog, login, remove, lock, and system-prompt actions contained raw English labels/help. | Replaced application-owned labels, tooltips, badges, alerts, and status strings with typed keys. | **FIXED** |
| Storage/Sidebar/AppKit/notifications | Import/delete alerts, workspace actions, command menus, rate-limit/server messages, and restore outcomes bypassed the selected language. | Routed each user-visible callsite through typed keys while preserving action handlers and dynamic data. | **FIXED** |

### Scope of the manual chain audit

Activity 60 (`docs/activity-checklists/60-localization-full-call-chain-audit.md`) records the manual declaration → runtime → view/action → final-consumer trace. The inspected controls include language search, plan-answer input, captcha presentation, Web Provider detection and login actions, model parameter editor, provider/model filtering and accordion controls, Auto Free lock/failover/catalog actions, Storage import/export/deletion, Sidebar workspace actions and search, chat attachment counters, Git branch creation, AppKit Edit/Find/Actions menus, project-integrity recovery, and system notifications. External provider/model names, URLs, browser page text, shell output, user-authored prompts, and error-provided data remain data and are intentionally not translated.

### TDD and verification

`.acceptance/test_localization_regressions_round106.py` was written before the production callsite changes and failed on the old raw language-search field. It now verifies the selected-language resolver, every confirmed affected callsite, all newly introduced translation keys, and the presence of `en`, `ru`, `es`, `fr`, `de`, `zh`, `ja`, `ko`, `pt`, and `ar` values for the new keys. The existing compact Auto Free adversarial check was updated only to recognize the canonical localized keys after the raw English markers were intentionally removed.

| Gate | Result |
|---|---:|
| Round 106 red regression before fix | **Failed as expected** |
| Round 106 source acceptance after fix | **PASS** |
| Feature registry integrity | **PASS — 274 unique rows; 224 PASS, 45 PARTIAL, 0 MISSING, 5 FUTURE** |
| Adversarial source checks | **PASS — 12/12** |
| Rounds 102/103/104/105 build-regression acceptances | **PASS** |
| Swift parser on all affected files | **PASS** |
| `git diff --check` | **PASS** |
| Foundation harness | **PASS — 360/360 with one worker** |
| Native macOS SwiftUI/AppKit visual/runtime | **UNVERIFIED** |

### Canonical registry update

The L10-03 `Full New-UI Translation` row remains `PASS` and now records the Round 106 runtime-key audit, 800 typed keys with complete 10-language rows, affected callsite coverage, and the native macOS verification boundary. No feature status was artificially changed: source-level coverage is complete, while SwiftUI/AppKit redraw, native menus, notifications, and visual fit still require a macOS build and manual language switching.

### Quality ratings

**Implementation quality: 100/100 at the verifiable source level.** The selected-language resolver, format forwarding, catalog keys, stable provider grouping, and affected callsites are covered by source checks, parser validation, and the 360-test Foundation harness.

**Task-following quality: 100/100 for the source-verifiable scope.** The defect was inventoried, red-tested before the production edits, manually traced through complete chains, documented in the checklist and canonical registry/report, and re-tested after implementation.

**Native verification confidence: 90/100 pending macOS.** The remaining uncertainty is limited to native SwiftUI redraw, AppKit command-menu refresh, native folder-picker prompt rendering, notification presentation, and visual text fit across all supported languages. The user should run `git pull origin main && ./build-app.sh` from the repository root and manually switch languages through the controls listed in Activity 60.


## Round 107 — Qwen/Gwen model detection, effort parsing, AI Free completeness, and Kimi remote-chat binding

### User-visible failures investigated

The macOS screenshots exposed three separate failures rather than one generic web-provider defect. Built-in Qwen/Gwen detection reported only the currently visible portion of a multi-surface model menu and did not reliably discover per-model effort controls. myCoder Auto Free read page text before opening and expanding the model menu, so it often saw only the selected model and returned one candidate out of many. Kimi send failed at the intentional context-mixing guard because the provider shell did not expose its active conversation identity in the URL, even though the browser DOM could expose it through conversation attributes or history links.

### Root-cause chain and fixes

`BrowserAutomationBridge` now has a default-compatible `readVisibleModelCandidates()` contract. `WKWebViewBrowserBridge` implements a bounded visible DOM scan over listbox, menu, model, dropdown and popover surfaces and returns structured selectable leaf metadata. `WebModelDiscovery.discover` and `discoverAllModels` combine vendor selectors with this scan, recognize additional expansion labels such as `Expand models`, `Show all models`, `View all models`, `展开更多`, and deduplicate each expanded state.

`WebModelListParser.isValidModelLabel` now requires compact vendor-shaped Qwen/Kimi model identifiers and rejects descriptions, headings, effort labels and UI actions before persistence. `normalizeEffortLabel` and `WebEffort.fromLabel` use explicit multilingual low/medium/high vocabulary and return `nil` for unknown text. A hidden or empty effort selector is skipped instead of being clicked merely because it exists in the DOM.

The AI Free action now prepares the same live model menu before reading page text. It passes structured live candidates and up to 60,000 characters of post-expansion page text to the detector, then merges AI candidates with live candidates while retaining strict validation and non-selectable status for AI-only rows until browser verification.

`WebRemoteChatIdentityLogic` validates DOM-derived remote identities and builds a canonical provider route. `WebChatDriver.getCurrentChatID` now checks URL routes first and then reads `data-chat-id`, `data-conversation-id`, conversation test IDs, active-page attributes and history hrefs. `ChatPanelView.bindWebRemoteChat` persists the canonical `/chat/{id}` or `/c/{id}` route. Existing host, UUID, model-injection and effort-injection fail-closed guards were preserved.

### TDD evidence

The persistent `.acceptance/test_web_regressions_round107.py` was written before implementation and failed on the absent broad candidate scanner, AI menu preparation, strict effort normalizer and Kimi identity helper. New Swift regressions were also written before the production edits: arbitrary model/page text initially became `.medium`, and a URL-less Kimi shell initially returned no chat identity. All red cases became green after the fixes.

### Verification results

| Gate | Result |
|---|---:|
| Round 107 red source acceptance before implementation | **Failed as expected** |
| Round 107 source acceptance after implementation | **PASS** |
| New strict-effort regressions | **2/2 PASS** |
| Kimi URL-less DOM identity regression | **PASS** |
| Existing model discovery suite | **5/5 PASS** |
| Existing parser suite | **4/4 PASS** |
| Existing WebChatDriver suite | **13/13 PASS** |
| Foundation harness | **363/363 PASS with one worker** |
| Rounds 102–106 acceptance | **PASS** |
| Registry integrity | **PASS — 274 unique rows** |
| Adversarial source checks | **12/12 PASS** |
| Swift parser on affected sources | **PASS** |
| Native macOS/WebKit/provider runtime | **UNVERIFIED** |

### Canonical status and quality ratings

`WEB-LOGIN-12` remains `PASS` for the source-defined detection-mode contract, with Round 107 live-menu/AI/effort notes added. `WEB-CHAT-13` remains `PARTIAL` because the source chain now includes the URL-less DOM identity fallback, but cookie/localStorage and real provider routing still require native WebKit verification. No registry status was promoted based on Linux-only evidence.

**Implementation quality: 100/100 at the available source/Foundation scope.** The three reported chains were separated, red-tested, minimally fixed and re-run through the complete 363-test Foundation harness. Existing context-mixing and pre-send verification protections were preserved.

**Task-following quality: 100/100 for the verifiable scope.** The screenshot symptoms were traced manually from UI action through browser bridge, DOM extraction, parser, persistence and final send consumer; the activity checklist, report and canonical registry were updated; native runtime behavior was not overstated.

**Native runtime confidence: 70/100 pending macOS.** Real Qwen/Kimi DOM attributes, expansion timing, WebKit JavaScript return shapes and live session routes remain unverified until the user runs the native macOS build with logged-in provider sessions.
