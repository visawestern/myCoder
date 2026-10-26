# Activity 46 — Storage Maintenance and Shell Truthfulness

## Audit objective

This round audits **STO-30**, **STO-31**, and **SHELL-01 through SHELL-03** from visible Settings/top-shell actions through validation, database selection, asynchronous refresh, status computation, and user feedback. The audit includes negative and empty inputs because storage and shell indicators are safety-critical: a false success or wrong database is worse than a visible no-op. It also validates the CSV schema itself so a documentation field shift cannot silently change a story’s status.

## Full chain checklist

| Story | Chain audited | Expected behavior | Result |
|---|---|---|---|
| STO-30 | Storage Settings archive/delete/vacuum controls → AppState maintenance → legacy DB + every project DB → vacuum/UI refresh | Archive/delete operate across legacy compatibility storage and every project DB; ages are nonnegative; destructive actions are confirmed; stats refresh after completion. | **Fixed Round 92 legacy negative-age divergence; source/parser and project tests pass; native SQLite maintenance UNVERIFIED.** |
| STO-31 | Storage stats load → legacy snapshot + project snapshots → deterministic aggregate → StorageSettings cards | Sizes, messages, active/archived counts include project stores once each and remain deterministic. | **Pass by source/tests; live SQLite and visual settings runtime UNVERIFIED.** |
| SHELL-01 | Workspace/session selection → branch/goal state → project DB hydration → TopBar badges | Branch appears only with project context; goal belongs to active session/project, is trimmed when stored, and whitespace clears it. | **Fixed Round 92 goal normalization; source/tests pass; SwiftUI/SQLite runtime UNVERIFIED.** |
| SHELL-02 | Selected route → AppState connectivity → provider-family status helper → StatusBar connection/model | Serve health cannot mask Auto Free/web/local/custom route state; effective route model is displayed; disconnected web/custom routes are not shown as connected. | **Pass by source/tests; live provider/WebKit and visual runtime UNVERIFIED.** |
| SHELL-03 | TopBar copy/undo/goal/terminal actions → NotificationCenter/AppState → visible result; endpoint helper → StatusBar | Copy reports success only after a nonempty transcript is written; undo no-op is a warning and failure is red; endpoint labels never show invalid `:0` data. | **Fixed Round 92 tone/endpoint/copy contracts; copy and native clipboard/undo UI UNVERIFIED.** |

## Detailed manual trace

| # | Action/function | Chain and invariant | Result |
|---:|---|---|---|
| 1 | Auto-archive picker | Only 3/7/14/30/90-day choices reach `archiveOldSessions`; button runs archive then refreshes stats. | **Pass by source.** |
| 2 | Delete-old confirmation | Picker values are 7/30/90/180/365; destructive action requires an alert confirmation, deletes across stores, then refreshes. | **Pass by source.** |
| 3 | Delete-archived confirmation | Permanent deletion is behind a separate alert; count is returned and UI refreshes. | **Pass by source.** |
| 4 | Compress database | `vacuumDatabase` runs legacy and every project DB; project-row vacuum creates/prunes backup first. | **Pass by source; SQLite/filesystem UNVERIFIED.** |
| 5 | Negative maintenance API input | Legacy DB previously used raw negative days and could target future sessions; project DB already clamped. Both paths now clamp with `max(0, days)`. | **Fixed Round 92.** |
| 6 | Storage stats aggregation | Legacy snapshot is included once; project snapshots are keyed by project ID and sorted; snapshot bytes remain separate. | **Pass by source/tests.** |
| 7 | Workspace branch badge | TopBar uses `ProjectHeaderContextLogic`; no selected workspace/legacy project shows myCoder fallback instead of stale branch. | **Pass by source/tests.** |
| 8 | Session goal setter | `/goal`/goal panel setter trims text, stores nil for whitespace-only input, updates selected/in-memory session, and writes through `DatabaseBridge`. | **Fixed Round 92.** |
| 9 | Goal hydration | Project-stored goal wins over stale legacy value; compatibility fallback is used only when project value is empty. | **Pass by source/tests.** |
| 10 | Selected route connection | Server, Auto Free, web, local, and custom routes use their own readiness sources; Serve cannot masquerade as another route. | **Pass by source/tests.** |
| 11 | Effective model label | Status bar prefers route-resolved effective model and falls back to selected model only when effective is blank. | **Pass by source/tests.** |
| 12 | Endpoint label | Only a selected connected Serve provider with a nonblank host and port 1–65535 gets `host:port`; all other routes show their selected ID. | **Fixed Round 92.** |
| 13 | Copy chat action | TopBar posts an intent; ChatPanel builds sanitized transcript and writes only nonempty content to NSPasteboard; completion event drives the checkmark. | **Fixed Round 92 source chain; AppKit clipboard UNVERIFIED.** |
| 14 | Undo action | AppState invokes project undo manager, refreshes Git only after `.undone`, and publishes explicit tone/message for success, no-op, or failure. | **Fixed Round 92.** |
| 15 | Goal/terminal buttons | TopBar toggles `showGoal`/`showTerminal`; ContentView presents `RightPanelView`/`BottomPanelView`. | **Pass by source.** |
| 16 | Empty/no-session copy | Empty transcript emits unavailable, so a stale green checkmark is cleared rather than asserted. | **Fixed Round 92 source; AppKit/SwiftUI interaction UNVERIFIED.** |

## Confirmed defects and TDD evidence

### STO-30 — legacy maintenance accepted negative ages

`ProjectDatabaseManager` already used `max(0, days)`, but `DatabaseManager.archiveSessionsOlderThan` and `deleteSessionsOlderThan` used raw negative values. A negative age moves the cutoff into the future and can archive or delete current sessions. A macOS in-memory red regression was written first for both operations. The legacy methods now clamp at zero to match project-scoped behavior.

### SHELL-01 — whitespace goals were persisted as nonempty values

`setCurrentSessionGoal` used `goal.isEmpty` rather than trimming. The display helper trimmed later, but the stored session could contain whitespace and meaningful goals retained accidental padding. Red normalization tests were written first. `SessionGoalPersistenceLogic.normalizedGoal` is now the shared normalization contract for hydration and setter persistence.

### SHELL-03 — undo no-op and copy action reported false success

TopBar inferred undo failure from the literal `Undo failed` prefix, causing `Nothing to undo.` to render as a green checkmark. The red tone tests were written first; the explicit `UndoActionFeedbackTone` now drives icon/color. Separately, the Copy button set its checkmark immediately, while ChatPanel silently returned for an empty transcript or clipboard failure. Red copy-result tests were written first; ChatCopyLogic now classifies empty/copyable results and completion events drive the checkmark only after a successful write.

### Canonical registry — STO-28 status field was shifted by missing CSV quotes

A persistent registry red test was extended to require every row’s `status` field to be one of `PASS`, `PARTIAL`, `MISSING`, or `FUTURE`. It failed on STO-28 because a comma-containing expected-behavior sentence was unquoted, shifting the coverage, status, and notes columns. The expected behavior is now correctly quoted; the registry parses as 274 rows with 274 unique IDs and the intended 224 PASS, 44 PARTIAL, 1 MISSING, and 5 FUTURE distribution.

### SHELL-03 — invalid endpoint labels were displayed as trusted Serve endpoints

`endpointLabel` returned `host:port` whenever the selected ID matched a server provider, even for an empty host, port zero, or empty selected ID. Red edge tests were written first. The helper now fails closed to the selected provider label and only formats valid ports 1–65535 with a nonblank trimmed host.

## Evidence

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

## Status and scores

The confirmed source-level storage and shell truthfulness defects are fixed. The stories remain **PARTIAL** wherever confirmation depends on macOS SQLite, AppKit clipboard, SwiftUI rendering, native undo, or live provider/WebKit state.

| Story | Code quality | Task adherence | Target-runtime confidence |
|---|---:|---:|---:|
| STO-30 | 98/100 | 100/100 | 0/100 |
| STO-31 | 97/100 | 100/100 | 0/100 |
| SHELL-01 | 98/100 | 100/100 | 0/100 |
| SHELL-02 | 97/100 | 100/100 | 0/100 |
| SHELL-03 | 98/100 | 100/100 | 0/100 |

> A storage button that accepts a negative age can destroy current data, and a checkmark shown before a clipboard write succeeds is not feedback—it is a false claim. Both boundaries now fail closed in source logic.
