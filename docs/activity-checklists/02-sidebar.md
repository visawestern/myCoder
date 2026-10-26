# Activity 02 — Sidebar

Источник: `Sources/Views/SidebarView.swift`, `Sources/Services/SidebarWorkspaceLogic.swift`,
`Sources/Services/WorkspaceArchiveVisibilityLogic.swift`,
`Sources/Services/SidebarSessionLimitLogic.swift`,
`Sources/Services/SidebarExpansionLogic.swift`,
`Sources/Services/NotificationActionRoutingLogic.swift`.

## Control and action inventory

| # | Действие | Trigger → handler → state/persistence → consumer/result | Ожидаемое поведение | Code quality | Task fit | Runtime status |
|---|---|---|---|---:|---:|---|
| 1 | Back/Forward | chevron button → `navigateBack()`/`navigateForward()` → navigation history/index → `selectedWorkspace` and main content | Переход по истории workspace; buttons disabled at boundaries; no out-of-bounds mutation | 95/100 | 100/100 | UNVERIFIED — macOS interaction required |
| 2 | Toggle sidebar | sidebar icon → `sidebarVisible.toggle()` → `ContentView` conditional branch → main content expands | Меняет visibility without losing selection or composer state | 95/100 | 100/100 | UNVERIFIED — macOS interaction required |
| 3 | Expand/collapse Workspaces | chevron or compact overflow → `workspacesSectionExpanded.toggle()` → conditional workspace list → visible rows | Переключает секцию and keeps all secondary controls reachable in compact width | 95/100 | 100/100 | UNVERIFIED — macOS hit-target required |
| 4 | Overview | all-workspaces icon/menu → `showWorkspacesOverview` → `WorkspacesOverviewSheet` → row selection sets workspace and dismisses | Открывает обзор workspace; search filters; selecting a row closes sheet and preserves context | 90/100 | 100/100 | UNVERIFIED — macOS sheet required |
| 5 | Archive popover | archive icon/overflow → `showArchivePopover` → `ArchivedProjectsPopover` reads registry → Restore saves registry and refreshes AppState | Показывает archived projects, restores immediately, and does not leave stale sidebar state | 95/100 | 100/100 | UNVERIFIED — macOS popover/storage runtime required |
| 6 | Workspace search | search icon → `showWorkspaceSearchField` and `workspaceFilterQuery` → `SidebarWorkspaceLogic.filtered` → displayed rows | Фильтрует by workspace name; closing search clears query | 95/100 | 95/100 | UNVERIFIED — macOS keyboard/UI required |
| 7 | Sort menu | menu selection → `workspaceSortOrder` → `SidebarWorkspaceLogic.sorted` → list/grid order | Сортирует name ascending/descending, recent session, or session count | 95/100 | 95/100 | UNVERIFIED — macOS menu required |
| 8 | Filter menu | menu selection → `workspaceFilterPreset` → session-count filter → displayed rows | All/has sessions/empty states are explicit and consistent with current sessions | 95/100 | 95/100 | UNVERIFIED — macOS menu required |
| 9 | List/grid | view button/menu → `workspaceViewMode` → list or `WorkspaceGridView` → selectable workspace cards | Меняет режим без losing selected workspace; grid cards remain keyboard/click targets | 90/100 | 95/100 | UNVERIFIED — macOS layout required |
| 10 | Workspace row | name/chevron button → selects workspace and expansion policy → AppState selected workspace → sessions and composer context | Выбирает workspace and shows its sessions; selecting another workspace expands that section | 95/100 | 100/100 | UNVERIFIED — macOS state transition required |
| 11 | Session row | session button → `selectSession(session)` → selected workspace/session, messages and Git context reload → ChatPanelView | Открывает session/chat and keeps project context; active row is visibly selected | 95/100 | 100/100 | UNVERIFIED — macOS/DB runtime required |
| 12 | New task | sidebar/row plus → `startNewTask(in:)` → new session state/DB and input focus request → composer | Создает a task in the chosen workspace and focuses the composer; no accidental provider switch | 90/100 | 100/100 | UNVERIFIED — macOS/DB runtime required |
| 13 | New project | action row → `showProjectCreation` → `NewProjectSheet` → DB + registry upsert → workspace list reload | Открывает NewProjectSheet and makes the new workspace selectable | 95/100 | 100/100 | UNVERIFIED — macOS file-panel/DB runtime required |
| 14 | Context menu | session hover menu → Finder/new task handlers → AppKit Finder or AppState task creation | Open session directory or create task; native Finder behavior remains runtime-only | 90/100 | 95/100 | PARTIAL — source traced; native QA pending |
| 15 | Notifications | bell → `showNotifications` → `NotificationsSheet`; action button → route; mark-all → service unread state | Открывает sheet; Mark All Read clears badge; supported action routes mark read and dismiss on success; missing session/custom no-op stays visible | 95/100 | 100/100 | UNVERIFIED — macOS sheet interaction required |
| 16 | Settings | gear → `openSettings()` → settings overlay → selected settings tab | Открывает settings without losing workspace/session context | 95/100 | 100/100 | UNVERIFIED — macOS overlay required |
| 17 | User footer | profile display → `UserProfileDisplay` → initials/name render; bell/settings actions consume state | Показывает stable initials/name and accessible icon hit targets | 90/100 | 95/100 | UNVERIFIED — macOS/AppKit identity required |

## Round 50 adversarial findings and fixes

### SID-05 — Archive state was disconnected from the active sidebar list

`ArchivedProjectsPopover` read and mutated `ProjectRegistryLogic`, while `AppState.workspaces`
was loaded independently from the project database. The sidebar applied only name/session filters,
so archive/restore had no immediate, coherent effect on visible workspace rows. A restored project
could remain stale until a later reload, and an archived project could continue to appear as active.

TDD was red first in `SidebarArchiveVisibilityLogicTests`: archived entries are hidden, restored
entries are visible, unknown legacy registry entries remain visible, and the currently selected
archived workspace remains visible to preserve active task context. The fix adds
`WorkspaceArchiveVisibilityLogic`, a published registry snapshot in `AppState`, refresh hooks after
Sidebar Restore and Storage Settings mutations, and active-context preservation. Linux harness:
**4/4 tests passed**.

### SID-07 — Session list silently showed ten despite the canonical twelve-row contract

The canonical CSV promised “up to 12 sessions”, but `WorkspaceSidebarSection` used
`workspaceSessions.prefix(10)` with no “more” affordance. The first ten sessions were indeed sorted,
but sessions 11 and 12 were inaccessible from the sidebar. TDD added
`SidebarSessionLimitLogicTests` for 12, fewer-than-12, empty, and explicit-limit cases. The view now
uses `SidebarSessionLimitLogic.maximumVisible == 12`. Linux harness: **3/3 tests passed**.

### SID-06 — Selection did not reliably drive expansion

The section state was initialized from `startsExpanded` only once. After selecting a different
workspace, the new section could remain collapsed and the previous section could remain expanded,
contrary to the intended active-project-first behavior. TDD added `SidebarExpansionLogicTests` for
current-row toggling, different-row expansion, and selected-section state. The view now uses the
pure logic for click behavior and `onChange(of: appState.selectedWorkspace?.id)` to synchronize each
section. Linux harness: **3/3 tests passed**.

### SID-15 — Notification action buttons could leave the sheet open

`NotificationRow.handleAction` routed Open Session, Open Settings, and View Changes but never
called `dismiss()`. The visible action therefore appeared to do nothing if the user did not manually
close the sheet. Child-button taps also could bypass the row-level mark-read gesture. TDD added
`NotificationActionRoutingLogicTests` for successful and failed session routing, custom no-op actions,
and mark-read-before-routing. The fix explicitly marks the notification read, dismisses supported
successful actions, preserves the sheet for a missing session or custom no-op, and leaves stateful
routing to AppState. Linux harness: **3/3 tests passed**.

## User story

As a user, I can select a workspace or session and start a task without losing the selected project
context. Sidebar archive state, session visibility, selection expansion, and notification actions
remain coherent immediately after each button action rather than only after relaunch.

The full target-runtime result remains **UNVERIFIED** in this Linux sandbox: SwiftUI, AppKit,
NSOpenPanel/Finder, native sheets/popovers, and macOS keyboard/hit-target behavior require the
user's macOS build. Code-level behavior is covered by pure Foundation tests and source tracing, not
claimed as macOS PASS.

```text
/goal go over every single feature in this file create a user story with expected behaviour based on the code keep a single canonical spreadsheet tracking the features status
• when done switch loop to testing every user story and documenting all errors
• when done fix every logistical or UX error
• test every user behaviour again post fix
```
