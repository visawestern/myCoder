# Hardcoded Strings — Localization Checklist

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
- [ ] 🔴 Line 52: `Button("Load earlier messages")` → use `L.t(AppLocalizationKey.locLoadingOlderMessages)` ✅ exists
- [ ] 🔴 Line 857: `msg.content = "Generation stopped"` → add `locGenerationStopped`
- [ ] 🔴 Line 1285: `msg.content = "Task completed"` → add `locTaskCompleted`

## MessageRowView.swift
- [ ] 🔴 Line 544: `label: "Result"` → add `locResult`
- [ ] 🔴 Line 537: `label: "Arguments"` → add `locArguments`
- [ ] 🔴 Line 464: `Text(isComplete ? "Completed" : "Running")` → add `locCompleted`, `locRunning`
- [ ] 🔴 Line 488: `tooltip: "Retry"` → use `locRetry` ✅ exists
- [ ] 🔴 Line 479: `tooltip: "Stop"` → use `locStop` ✅ exists
- [ ] 🔴 Line 223: `tooltip: message.role == .user ? "Resend" : "Retry"` → add `locResend`, use `locRetry`
- [ ] 🔴 Line 199: `tooltip: copied ? "Copied" : "Copy"` → add `locCopied`, use `locCopyAll`

## SidebarView.swift
- [ ] 🔴 Line 785: `Button("New task")` → add `locNewTaskSidebar`
- [ ] 🔴 Line 782: `Button("Open in Finder")` → use `locShowInFinder`
- [ ] 🔴 Line 939: `Button("Restore")` → use `locRestore` ✅ exists
- [ ] 🔴 Line 349: `Button("Mark All Read")` → add `locMarkAllRead`
- [ ] 🔴 Line 24: `panel.message = "Select a folder to open as a project"` → add `locSelectFolder`
- [ ] 🔴 Line 23: `panel.prompt = "Open"` → use `locOpen` ✅ exists

## WebProvidersSection.swift
- [ ] 🔴 Line 38: `Text(... ? "Configured" : "Add")` → add `locConfigured`, use `locAdd`
- [ ] 🔴 Line 184: `Button("Log in")` → add `locLogin`
- [ ] 🔴 Lines 224, 469: help strings → already mostly translated
- [ ] 🔴 Line 730: `Button("Cancel")` → use `locCancel` ✅ exists
- [ ] 🔴 Line 732: `Button("Use as Model Selector")` → add `locUseAsModelSelector`

## InputControls.swift
- [ ] 🔴 Line 245: `Button("Reset")` → use `locReset` ✅ exists
- [ ] 🔴 Line 248: `Button("Save")` → use `locSave` ✅ exists
- [ ] 🔴 Line 518: `Button("Cancel")` → use `locCancel` ✅ exists
- [ ] 🔴 Line 521: `Button("Connecting…" / "Connect")` → add `locConnecting`, use `locConnect`

## InputViews.swift
- [ ] 🔴 Line 46: `.help("Show in Finder")` → use `locShowInFinder`
- [ ] 🔴 Line 432: `"Select workspace"` → use `locSelectWorkspace`
- [ ] 🔴 Line 645: `TextField("Search workspaces")` → use `locSearchWorkspaces`

## NewProjectSheet.swift
- [ ] 🔴 Line 54: `.help("Choose folder")` → add `locChooseFolder`
- [ ] 🔴 Line 62: `Button("Cancel")` → use `locCancel`
- [ ] 🔴 Line 32: `TextField("My Project")` → add `locMyProject`

## GitPremiumDialogs.swift
- [ ] 🔴 Line 440: `TextField("Short summary of the change")` → add `locShortSummary`
- [ ] 🔴 Line 448: `TextField("What changed and why")` → add `locWhatChanged`

## BottomPanelView.swift
- [ ] 🔴 Line 445: `Button("Cancel")` → use `locCancel`
- [ ] 🔴 Line 444: `Button("Create")` → use `locCreate`
- [ ] 🔴 Line 443: `TextField("Branch name")` → add `locBranchName`
- [ ] 🔴 Line 442: `.alert("Create New Branch")` → add `locCreateNewBranch`

## ChatImageViews.swift
- [ ] 🔴 Line 36: `.help("View image")` → add `locViewImage`
- [ ] 🔴 Line 96: `Button("Close")` → use `locClose` ✅ exists

## ContentView.swift
- [ ] 🔴 Line 113: `Button("Ignore")` → add `locIgnore`
- [ ] 🔴 Line 100: `Button("Restore from backup")` → add `locRestoreFromBackup`

## StatusBarView.swift
- [ ] 🔴 Line 14: `"Connected" / "Disconnected"` → add `locConnected`, `locDisconnected`

## MyCoderApp.swift (CommandMenu)
- [ ] 🔴 Line 24: `Button("Cut")` → macOS system — can stay (system menu)
- [ ] 🔴 Line 29: `Button("Copy")` → macOS system — can stay
- [ ] 🔴 Line 34: `Button("Paste")` → macOS system — can stay
- [ ] 🔴 Line 43: `Button("Select All")` → macOS system — can stay
- [ ] 🔴 Line 49: `Button("New Task")` → use `locNewTask`
- [ ] 🔴 Line 54: `CommandMenu("Find")` → system — can stay
- [ ] 🔴 Line 60: `CommandMenu("Actions")` → system — can stay
- [ ] 🔴 Line 61: `Button("Undo Last File Change")` → add `locUndoLastFileChange`

## TopBarView.swift
- [ ] 🔴 Line 55: `label: "Goal"` → add `locGoal`
- [ ] 🔴 Line 62: `label: "Terminal"` → add `locTerminal`

## TaskHeaderView.swift
- [ ] 🔴 Line 70: `.help("Terminal")` → add `locTerminal`
- [ ] 🔴 Line 62: `.help(chatCopied ? "Copied" : "Copy entire chat")` → use `locCopied`, add `locCopyChat`

## ModelSettingsView.swift
- [ ] 🔴 Line 316: `message.hasPrefix("Loaded")` → check prefix only
- [ ] 🔴 Lines 841, 844: `result.contains("Success")` → check prefix only

## Element Picker (WebProvidersSection.swift)
- [ ] 🔴 Line 469: `"Pick an element on the page..."` → add `locPickElement`

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

- [x] Web provider login strings (locWebXxx)
- [ ] Chat panel strings
- [ ] Message row strings
- [ ] Sidebar strings
- [ ] Input controls strings
- [ ] Git/branch strings
- [ ] Element picker strings
- [ ] Status bar strings
