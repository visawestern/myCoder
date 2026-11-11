# Hardcoded Strings — Localization Checklist

> **Архив, 2026-11-11.** Список от 2026-08-09 устарел: номера строк и часть
> подписей с тех пор изменились. Действующая проверка — автоматическая:
> `myCoder/Tests/HardcodedStringAuditTests.swift` сканирует исходники и падает
> на новой захардкоженной английской подписи; полноту таблицы переводов держат
> тесты `AppLocalization` (все ключи, отсутствие пересечений английских значений,
> поздние строки). Технические токены (`/compact`, `MI`, `/name`,
> `localhost:11434 or 192.168.1.10:4096`, `R`, `T`, `⌘⇧P`) — белый список
> сканера, это не пользовательские подписи. Ниже — история, а не открытая работа.

> Generated: 2026-08-09
> Total hardcoded strings found: ~66
> Status: 🔴 = not translated, 🟢 = translated (via L.t)

## Summary

| Status | Count |
|--------|-------|
| 🔴 Not translated | 66 |
| 🟢 Translated | 1 (web provider strings added earlier) |
| 🟡 Partial | 0 |

## Legend

- 🔴 Replace with `L.t(AppLocalizationKey.locXxx)` + add key to AppLocalization.swift
- 🟢 Already localized
- 🟡 Partially (some languages missing)

---

## ChatPanelView.swift
- [x] 🟢 Line 52: `Button("Load earlier messages")` → use `L.t(AppLocalizationKey.locLoadingOlderMessages)` ✅ exists
- [x] 🟢 Line 857: `msg.content = "Generation stopped"` → add `locGenerationStopped`
- [x] 🟢 Line 1285: `msg.content = "Task completed"` → add `locTaskCompleted`

## MessageRowView.swift
- [x] 🟢 Line 544: `label: "Result"` → add `locResult`
- [x] 🟢 Line 537: `label: "Arguments"` → add `locArguments`
- [x] 🟢 Line 464: `Text(isComplete ? "Completed" : "Running")` → add `locCompleted`, `locRunning`
- [x] 🟢 Line 488: `tooltip: "Retry"` → use `locRetry` ✅ exists
- [x] 🟢 Line 479: `tooltip: "Stop"` → use `locStop` ✅ exists
- [x] 🟢 Line 223: `tooltip: message.role == .user ? "Resend" : "Retry"` → add `locResend`, use `locRetry`
- [x] 🟢 Line 199: `tooltip: copied ? "Copied" : "Copy"` → add `locCopied`, use `locCopyAll`

## SidebarView.swift
- [x] 🟢 Line 785: `Button("New task")` → add `locNewTaskSidebar`
- [x] 🟢 Line 782: `Button("Open in Finder")` → use `locShowInFinder`
- [x] 🟢 Line 939: `Button("Restore")` → use `locRestore` ✅ exists
- [x] 🟢 Line 349: `Button("Mark All Read")` → add `locMarkAllRead`
- [x] 🟢 Line 24: `panel.message = "Select a folder to open as a project"` → add `locSelectFolder`
- [x] 🟢 Line 23: `panel.prompt = "Open"` → use `locOpen` ✅ exists

## WebProvidersSection.swift
- [x] 🟢 Line 38: `Text(... ? "Configured" : "Add")` → add `locConfigured`, use `locAdd`
- [x] 🟢 Line 184: `Button("Log in")` → add `locLogin`
- [x] 🟢 Lines 224, 469: help strings → already mostly translated
- [x] 🟢 Line 730: `Button("Cancel")` → use `locCancel` ✅ exists
- [x] 🟢 Line 732: `Button("Use as Model Selector")` → add `locUseAsModelSelector`

## InputControls.swift
- [x] 🟢 Line 245: `Button("Reset")` → use `locReset` ✅ exists
- [x] 🟢 Line 248: `Button("Save")` → use `locSave` ✅ exists
- [x] 🟢 Line 518: `Button("Cancel")` → use `locCancel` ✅ exists
- [x] 🟢 Line 521: `Button("Connecting…" / "Connect")` → add `locConnecting`, use `locConnect`

## InputViews.swift
- [x] 🟢 Line 46: `.help("Show in Finder")` → use `locShowInFinder`
- [x] 🟢 Line 432: `"Select workspace"` → use `locSelectWorkspace`
- [x] 🟢 Line 645: `TextField("Search workspaces")` → use `locSearchWorkspaces`

## NewProjectSheet.swift
- [x] 🟢 Line 54: `.help("Choose folder")` → add `locChooseFolder`
- [x] 🟢 Line 62: `Button("Cancel")` → use `locCancel`
- [x] 🟢 Line 32: `TextField("My Project")` → add `locMyProject`

## GitPremiumDialogs.swift
- [x] 🟢 Line 440: `TextField("Short summary of the change")` → add `locShortSummary`
- [x] 🟢 Line 448: `TextField("What changed and why")` → add `locWhatChanged`

## BottomPanelView.swift
- [x] 🟢 Line 445: `Button("Cancel")` → use `locCancel`
- [x] 🟢 Line 444: `Button("Create")` → use `locCreate`
- [x] 🟢 Line 443: `TextField("Branch name")` → add `locBranchName`
- [x] 🟢 Line 442: `.alert("Create New Branch")` → add `locCreateNewBranch`

## ChatImageViews.swift
- [x] 🟢 Line 36: `.help("View image")` → add `locViewImage`
- [x] 🟢 Line 96: `Button("Close")` → use `locClose` ✅ exists

## ContentView.swift
- [x] 🟢 Line 113: `Button("Ignore")` → add `locIgnore`
- [x] 🟢 Line 100: `Button("Restore from backup")` → add `locRestoreFromBackup`

## StatusBarView.swift
- [x] 🟢 Line 14: `"Connected" / "Disconnected"` → add `locConnected`, `locDisconnected`

## MyCoderApp.swift (CommandMenu)
- [x] 🟢 Line 24: `Button("Cut")` → macOS system — can stay (system menu)
- [x] 🟢 Line 29: `Button("Copy")` → macOS system — can stay
- [x] 🟢 Line 34: `Button("Paste")` → macOS system — can stay
- [x] 🟢 Line 43: `Button("Select All")` → macOS system — can stay
- [x] 🟢 Line 49: `Button("New Task")` → use `locNewTask`
- [x] 🟢 Line 54: `CommandMenu("Find")` → system — can stay
- [x] 🟢 Line 60: `CommandMenu("Actions")` → system — can stay
- [x] 🟢 Line 61: `Button("Undo Last File Change")` → add `locUndoLastFileChange`

## TopBarView.swift
- [x] 🟢 Line 55: `label: "Goal"` → add `locGoal`
- [x] 🟢 Line 62: `label: "Terminal"` → add `locTerminal`

## TaskHeaderView.swift
- [x] 🟢 Line 70: `.help("Terminal")` → add `locTerminal`
- [x] 🟢 Line 62: `.help(chatCopied ? "Copied" : "Copy entire chat")` → use `locCopied`, add `locCopyChat`

## ModelSettingsView.swift
- [x] 🟢 Line 316: `message.hasPrefix("Loaded")` → check prefix only
- [x] 🟢 Lines 841, 844: `result.contains("Success")` → check prefix only

## Element Picker (WebProvidersSection.swift)
- [x] 🟢 Line 469: `"Pick an element on the page..."` → add `locPickElement`

---

## Keys That Already Exist (reuse these!)

| Key | English | Use For |
|-----|---------|---------|
| `locLoadingOlderMessages` | "Loading older..." | Load earlier messages |
| `locRetry` | "Retry" | Retry button |
| `locStop` | "Stop" | Stop button |
| `locRestore` | "Restore" | Restore button |
| `locShowInFinder` | "Show in Finder" | Finder buttons |
| `locCopyAll` | "Copy all" | Copy |
| `locCancel` | "Cancel" | Cancel buttons |
| `locClose` | "Close" | Close buttons |
| `locCreate` | "Create" | Create buttons |
| `locConnect` | "Connect" | Connect button |
| `locReset` | "Reset" | Reset button |
| `locSave` | "Save" | Save button |
| `locOpen` | "Open" | Open prompt |
| `locAdd` | "Add" | Add button |
| `locSearchWorkspaces` | "Search workspaces" | Search fields |
| `locSelectWorkspace` | "Select workspace" | Workspace placeholder |
| `locWebLoginTitle` | "Log in to" | Login header |
| `locWebDetectModels` | "Detect models" | Detect button |
| `locWebCaptureSession` | "Capture session & close" | Capture button |
| `locWebDetecting` | "Detecting models..." | Detecting state |
| `locWebModelsFound` | "models found" | Found count |
| `locWebNoSelector` | "No model selector..." | No selector error |
| `locWebNoModels` | "No models found..." | No models error |

## New Keys Needed (~30)

- `locGenerationStopped`
- `locTaskCompleted`
- `locResult`
- `locArguments`
- `locCompleted`
- `locRunning`
- `locResend`
- `locCopied`
- `locNewTask` / `locNewTaskSidebar`
- `locMarkAllRead`
- `locSelectFolder`
- `locConfigured`
- `locLogin`
- `locUseAsModelSelector`
- `locConnecting`
- `locChooseFolder`
- `locMyProject`
- `locShortSummary`
- `locWhatChanged`
- `locBranchName`
- `locCreateNewBranch`
- `locViewImage`
- `locIgnore`
- `locRestoreFromBackup`
- `locConnected`
- `locDisconnected`
- `locUndoLastFileChange`
- `locGoal`
- `locTerminal`
- `locCopyChat`
- `locPickElement`

---

## Progress

> Исторические отметки ниже заменены автоматическими проверками 2026-11-11.
> Открытых пунктов нет: сканер и тесты полноты переводов — источник истины.

- [x] Web provider login strings (locWebXxx)
- [x] Chat panel strings — заменено `AppLocalization.string(forEnglish:)` и сканером
- [x] Message row strings — заменено сканером
- [x] Sidebar strings — заменено `locAdd`/`locDisable`/`locEnable`/`locGoal`/`workspacesTitle`
- [x] Input controls strings — заменено сканером
- [x] Git/branch strings — заменено сканером
- [x] Element picker strings — заменено сканером
- [x] Status bar strings — заменено сканером
