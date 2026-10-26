# Activity 01 — App Shell

Источник: `Sources/Views/ContentView.swift`, `Sources/App/MyCoderApp.swift`,
`Sources/Services/MimoServeConnectionManager.swift`,
`Sources/Services/ServerConnectionReadinessLogic.swift`.

## Control and action inventory

| # | Контрол/действие | Trigger → handler → state/persistence → consumer/result | Ожидаемое поведение | Code quality | Task fit | Runtime status |
|---|---|---|---|---:|---:|---|
| 1 | WindowGroup | `MyCoderApp.body` → `WindowGroup` → root `ContentView` receives `appState` → macOS window renders | Открывает окно с min 900×600 и default 1200×750 | 100/100 | 100/100 | UNVERIFIED — requires macOS |
| 2 | Startup task | `ContentView.task` → `loadCustomProviders()` → `connectToServer()` → `ServerConnectionReadinessLogic` copies completed health result to `AppState.serverConnected` → sessions load from local DB; server models load only when the same health check is online → `providerOptions`/composer consume state | Без MiMo Serve приложение всё равно reaches a usable local/Auto Free composer; with a healthy server, server models are not skipped on first launch | 95/100 | 100/100 | UNVERIFIED — macOS UI/network runtime required |
| 3 | Sidebar visibility | `SidebarView` button → `appState.sidebarVisible` → `ContentView` conditional HStack branch → sidebar appears/disappears | Показывает/скрывает SidebarView without losing main content | 95/100 | 95/100 | UNVERIFIED — macOS UI required |
| 4 | Sidebar resize handle | drag/double-click → `SidebarResizeLogic.applyDrag` / reset → `@AppStorage("sidebarWidth")` → `ContentView` frame | Drag 200..420, double-click reset 260, persistence across launches | 95/100 | 100/100 | PARTIAL — logic tested; macOS drag/persistence runtime pending |
| 5 | TopBarView | root layout → `TopBarView` → app-state actions → header controls update state | Собирает one unified header without a second project-dependent header | 90/100 | 95/100 | UNVERIFIED — macOS UI required |
| 6 | ChatPanelView | root layout → `ChatPanelView` → selected session/messages or empty state → visible composer | Показывает empty state or message feed and keeps composer reachable without a selected project | 90/100 | 100/100 | UNVERIFIED — macOS UI required |
| 7 | BottomPanelView | `showTerminal` state → conditional divider/panel → terminal/Git controls consume selected session | Показывает terminal/Git panel only when enabled; status bar remains visible | 95/100 | 95/100 | UNVERIFIED — macOS UI required |
| 8 | RightPanelView | `showGoal` state → conditional divider/panel → goal/plan content consumes selected session | Показывает plan/Git panel only when enabled and does not duplicate the main header | 95/100 | 95/100 | UNVERIFIED — macOS UI required |
| 9 | Settings overlay | settings action → `showSettings` → overlay plus backdrop/Escape/close binding → state false | Открывается above the app and closes through backdrop, Escape, or close action | 95/100 | 100/100 | UNVERIFIED — macOS UI required |
| 10 | Search sheet | Cmd+K/menu → `showSearch` → `.sheet` presents `SearchPaletteView` → search selection updates app state | Открывает SearchPaletteView and returns focus to the workspace | 95/100 | 95/100 | UNVERIFIED — macOS UI required |
| 11 | Remote connection sheet | control → `showRemoteConnection` → `RemoteConnectionSheet` → `connectToServe(host:port)` → manager health + AppState state | Подключает host/port and reports unavailable state without blocking Auto Free/local composer | 90/100 | 100/100 | UNVERIFIED — macOS/network runtime required |
| 12 | New project sheet | sidebar/menu → `showProjectCreation` → `NewProjectSheet` → create/update project DB → workspaces reload | Создаёт project/workspace and makes it selectable | 95/100 | 95/100 | UNVERIFIED — macOS file-panel/DB runtime required |
| 13 | Git action sheet | slash/menu action → `pendingGitAction` → `GitActionSheet` switch → commit/review/publish/PR handler → visible result | Маршрутизирует each Git action to its real dialog; dismissing clears the pending action | 95/100 | 100/100 | UNVERIFIED — macOS/gh runtime required |
| 14 | Integrity alert restore/ignore | selected workspace didSet → async integrity check → `projectIntegrityAlert` → ContentView alert → restore backup or ignore | Corruption is visible and user can restore the latest backup or explicitly ignore | 95/100 | 100/100 | PARTIAL — logic/source tested; macOS alert/restore runtime pending |

## Round 49 adversarial chain result

The first story exposed a real defect. `ContentView.task` awaited
`AppState.connectToServer()`, but that method only awaited
`MimoServeConnectionManager.checkAvailability()` and never copied the completed result into
`AppState.serverConnected`. Consequently, a healthy local server could leave the AppState boolean
false; the following `async let models` branch then skipped `loadModelsFromServer()` on first
startup. This violated the startup chain even though the connection manager itself was healthy.

A red regression suite was added first in
`myCoder/Tests/ServerConnectionReadinessLogicTests.swift`. Because the full target requires
SwiftUI/AppKit and cannot compile in Linux, the same pure Foundation contract is mirrored in the
Linux harness and runs as an executable regression suite. The minimal fix adds
`ServerConnectionReadinessLogic` and synchronizes `serverConnected` after the completed health
check. Missing or cancelled health results fail closed.

The first user story is now code-level fixed. Target-runtime behavior remains **UNVERIFIED** until
this exact startup chain is exercised in the macOS build with both a healthy MiMo Serve and no
running server. The default free route is **myCoder Auto Free**; the historical “free MiMo-Auto
route” wording is obsolete and must not be used.

## User story

As a user, I can open myCoder and reach a usable composer without a running MiMo Serve because
**myCoder Auto Free** is available as the built-in free route. If MiMo Serve is healthy, its
server-backed model list is loaded after the completed health check rather than being skipped due
to stale AppState state.

```text
/goal go over every single feature in this file create a user story with expected behaviour based on the code keep a single canonical spreadsheet tracking the features status
• when done switch loop to testing every user story and documenting all errors
• when done fix every logistical or UX error
• test every user behaviour again post fix
```
