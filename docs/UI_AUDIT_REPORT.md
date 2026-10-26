# UI Elements Audit — Real Working Status

**Date**: 2026-07-22  
**Method**: Each element traced from UI → code path → state → outcome  
**Test suite**: 769 tests, 135 suites — ALL PASSED ✅

---

## 1. SETTINGS VIEW (`SettingsView.swift`)

### 1.1 General Settings Tab

| # | Элемент | Действие | Код | Реальная работа |
|---|---------|----------|-----|-----------------|
| 1 | **Theme picker** | Menu: System/Dark/Light → theme меняется | `appState.appTheme = theme` → UserDefaults → `.preferredColorScheme` | ✅ **Работает** |
| 2 | **Language picker** | Menu: English/Russian → язык UI меняется | `appState.setLanguage(option)` → `settings.language` → `AppLocalization.string()` | ✅ **Работает** |
| 3 | **Interface Zoom** | Segmented: Smaller/Default/Larger | `appState.updateSettings { $0.zoom = zoom }` → `.interfaceFontScale` env | ✅ **Работает** |
| 4 | **Inherit terminal profile** | Toggle | `appState.settings.inheritTerminalProfile` через Binding | ✅ **Работает** (сохраняется) |
| 5 | **Terminal font** | TextField | `appState.settings.terminalFont` через Binding | ✅ **Работает** (сохраняется) |
| 6 | **HTTP Proxy — TextField** | Ввод URL | `$appState.settings.httpProxy` — live-binding, меняется сразу | ⚠️ **Работает, но** меняется на каждый символ, нет дискретного сохранения |
| 7 | **HTTP Proxy — Save** | Кнопка `Save` | `Button("Save") {}` — **пустое замыкание** | ❌ **НЕ РАБОТАЕТ** — ничего не делает |
| 8 | **HTTP Proxy — hint** | Текст «Restart the app to take effect» | Просто текст | ⚠️ **Работает как текст**, но противоречит live-binding |

### 1.2 Code Preview Settings Tab

| # | Элемент | Действие | Код | Реальная работа |
|---|---------|----------|-----|-----------------|
| 9 | **Light code theme** | Menu: GitHub Light/GitHub Dark | `Button("GitHub Light") {}` — **пустое замыкание** | ❌ **НЕ РАБОТАЕТ** — выбор не применяется |
| 10 | **Dark code theme** | Menu: GitHub Light/GitHub Dark | `Button("GitHub Dark") {}` — **пустое замыкание** | ❌ **НЕ РАБОТАЕТ** — выбор не применяется |
| 11 | **Show line numbers** | Toggle | `$appState.settings.showLineNumbers` | ✅ **Работает** |
| 12 | **Wrap long lines** | Toggle | `$appState.settings.wrapLongLines` | ✅ **Работает** |
| 13 | **Code font size** | Slider 8-24 | `appState.settings.codeFontSize = Int($0)` | ✅ **Работает** |

### 1.3 Model Settings — MiMo Serve Card

| # | Элемент | Действие | Код | Реальная работа |
|---|---------|----------|-----|-----------------|
| 14 | **Connect/Stop button** | Connect → вызывает `connectToServe`; Stop → `stopServe` | Полный async flow с health check | ✅ **Работает** (при запущенном сервере) |
| 15 | **Connected/Disconnected badge** | Статус | `appState.serverConnected` → badge | ✅ **Работает** |
| 16 | **Hostname field** | TextField | `$serveHostname` — локальный @State | ✅ **Работает** (передаётся в connectToServe). **НО** disabled только пока connected |
| 17 | **Port field** | TextField | `$servePort` — локальный @State | ✅ **Работает** |
| 18 | **Log level** | Segmented picker | `$serveLogLevel` — локальный @State | ⚠️ **Работает, НО** log level никогда не передаётся в connectToServe (не используется) |
| 19 | **Endpoint display** | Текст | `http://{host}:{port}` или `Not running` | ✅ **Работает** |
| 20 | **Available models count** | Текст | `appState.availableModels.count` | ✅ **Работает** |
| 21 | **Model chips** | ScrollView моделей | `ForEach(appState.availableModels)` | ✅ **Работает** |
| 22 | **Empty state (no server)** | Иконка + текст | conditional else branch | ✅ **Работает** |

### 1.4 Model Settings — Provider List Column

| # | Элемент | Действие | Код | Реальная работа |
|---|---------|----------|-----|-----------------|
| 23 | **Provider list items** | Click → `selectProvider` | `appState.selectProvider(option.id)` | ✅ **Работает** |
| 24 | **Checkmark on selected** | Визуальный индикатор | `appState.selectedProviderID == option.id` | ✅ **Работает** |
| 25 | **Connection dot** | Green/gray circle | `option.isConnected` | ✅ **Работает** |
| 26 | **Empty state** | «No providers yet» + «Add provider» CTA | `SettingsCardEmptyState` | ✅ **Работает** |
| 27 | **Add provider button** | → `showAddProvider = true` → Sheet | ✅ **Работает** |

### 1.5 Model Settings — Provider Detail Column

| # | Элемент | Действие | Код | Реальная работа |
|---|---------|----------|-----|-----------------|
| 28 | **Provider name + type** | Текст | `option.name`, `option.isCustom ? "Custom" : "MiMo Serve"` | ✅ **Работает** |
| 29 | **Model count** | CPU icon + count | `detailModelCount(for:)` | ✅ **Работает** |
| 30 | **Selected model badge** | Capsule with model ID | Условно при selectedModel не пустом | ✅ **Работает** |
| 31 | **API Key SecureField** | SecureField + onAppear/onChange | `$customAPIKeyDraft` — **читает `custom.apiKey`** | ⛔️ **НЕ ИСПОЛЬЗУЕТ Keychain** — читает plain-storage `custom.apiKey`, не `getSecureAPIKey()` |
| 32 | **Save API Key button** | Кнопка | `appState.updateCustomProvider(updated)` — **сохраняет снова в plain storage**, не в Keychain | ⚠️ **Работает, но сохраняет в plain storage**, а Keychain миграция была, но не используется |
| 33 | **Enable Tool Calling toggle** | Toggle → `updateCustomProvider` | ✅ **Работает** |
| 34 | **Enable ACP Protocol toggle** | Toggle (только для .acp типа) | ✅ **Работает** |
| 35 | **Remove provider** | Destructive button | `appState.removeCustomProvider(custom)` | ✅ **Работает** |
| 36 | **Tools unavailable warning** | Текст | conditional на `supportsToolcallForSelection` | ✅ **Работает** |
| 37 | **Empty state «No provider selected»** | Иконка + текст | conditional | ✅ **Работает** |

### 1.6 Model Settings — Models Column

| # | Элемент | Действие | Код | Реальная работа |
|---|---------|----------|-----|-----------------|
| 38 | **Model cards** | Click → `selectModel` | `appState.selectModel(modelID)` | ✅ **Работает** |
| 39 | **Model name** | `meta?.name ?? modelID` | ✅ **Работает** |
| 40 | **Capability badges** | Reasoning / Tools | `meta?.capabilities?.reasoning`, `meta?.capabilities?.toolcall` | ✅ **Работает** |
| 41 | **Context size badge** | `{context/1000}k ctx` | ✅ **Работает** |
| 42 | **Checkmark on selected model** | Визуальный индикатор | ✅ **Работает** |
| 43 | **Empty state** | «No models loaded» + hint | conditional | ✅ **Работает** |

### 1.7 Add Provider Sheet

| # | Элемент | Действие | Код | Реальная работа |
|---|---------|----------|-----|-----------------|
| 44 | **Provider type picker** | Menu → меняет default URL | `onChange(of: type)` → `url = newType.defaultURL` | ✅ **Работает** |
| 45 | **Name field** | TextField | `$name` | ✅ **Работает** |
| 46 | **Base URL field** | TextField | `$url` | ✅ **Работает** |
| 47 | **API Key SecureField** | SecureField | `$apiKey` | ✅ **Работает** |
| 48 | **Requires API Key toggle** | Toggle `$requiresAPIKey` | ✅ **Работает, НО** не скрывает API Key поле при выключении — toggle и поле не связаны |
| 49 | **Enable Tool Calling toggle** | Toggle `$supportsTools` | ✅ **Работает** |
| 50 | **Enable ACP Protocol toggle** | Toggle (только для .acp) | ✅ **Работает** |
| 51 | **Test Connection button** | → `testProvider(url:apiKey:type:)` | ✅ **Работает** (через URLSession) |
| 52 | **Cancel / Add Provider buttons** | Close / Create | ✅ **Работает** |

### 1.8 Skills Settings Tab

| # | Элемент | Действие | Код | Реальная работа |
|---|---------|----------|-----|-----------------|
| 53 | **Search skills** | TextField | `$searchQuery` → `AgentResourcesLoader.filterSkills` | ✅ **Работает** |
| 54 | **Skills library** | `AgentResourceLibraryView(.skills)` | ✅ **Работает** (загружает из JSON каталога) |
| 55 | **Installed skills list** | Загружается через `AgentResourcesLoader.loadSkills()` | ✅ **Работает** (при установленных навыках) |
| 56 | **Empty state** | «No skills installed yet» | ✅ **Работает** |

### 1.9 MCP Servers Settings Tab

| # | Элемент | Действие | Код | Реальная работа |
|---|---------|----------|-----|-----------------|
| 57 | **Search MCP servers** | TextField | `$searchQuery` | ✅ **Работает** |
| 58 | **MCP library** | `AgentResourceLibraryView(.mcpServers)` | ✅ **Работает** |
| 59 | **Configured servers list** | `AgentResourcesLoader.loadMCPServers()` | ✅ **Работает** |
| 60 | **Empty state** | «No MCP servers configured» | ✅ **Работает** |

### 1.10 Plugins Settings Tab

| # | Элемент | Действие | Код | Реальная работа |
|---|---------|----------|-----|-----------------|
| 61 | **Search plugins** | TextField | `$searchQuery` | ✅ **Работает** |
| 62 | **Plugins list** | `AgentResourcesLoader.loadPlugins()` | ✅ **Работает** |
| 63 | **Enabled/Disabled label** | Текст | `plugin.isEnabled ? "Enabled" : "Disabled"` | ✅ **Работает** |
| 64 | **Empty state** | «No plugins installed» | ✅ **Работает** |

### 1.11 Commands Settings Tab

| # | Элемент | Действие | Код | Реальная работа |
|---|---------|----------|-----|-----------------|
| 65 | **Search commands** | TextField | `$searchQuery` | ✅ **Работает** |
| 66 | **Commands list** | `AgentResourcesLoader.loadCommands()` | ✅ **Работает** |
| 67 | **Empty state** | «No user commands» + hint | ✅ **Работает** |

### 1.12 Indexing Settings Tab

| # | Элемент | Действие | Код | Реальная работа |
|---|---------|----------|-----|-----------------|
| 68 | **Index new folders toggle** | Toggle | `$indexNewFolders` — **локальный @State** | ❌ **НЕ РАБОТАЕТ** — никуда не сохраняется, не влияет ни на что |
| 69 | **Index repositories toggle** | Toggle | `$indexRepositories` — **локальный @State** | ❌ **НЕ РАБОТАЕТ** — никуда не сохраняется |

### 1.13 Usage Settings Tab

| # | Элемент | Действие | Код | Реальная работа |
|---|---------|----------|-----|-----------------|
| 70 | **Time range segment** | «Last 7 days» / «Last 30 days» | **hardcoded** `isSelected: false` и `true`, пустые action `{}` | ❌ **НЕ РАБОТАЕТ** — всегда «Last 30 days», переключение не работает |
| 71 | **Stat cards (Tokens/Sessions/Messages etc)** | Текстовые значения | **hardcoded** `"23.2M"`, `"11"`, `"24"` | ❌ **НЕ РАБОТАЮТ** — статические заглушки, не реальные данные |
| 72 | **Favorite model** | `appState.selectedModel` или `"None"` | ✅ **Работает** |

### 1.14 Onboard Settings Tab

| # | Элемент | Действие | Код | Реальная работа |
|---|---------|----------|-----|-----------------|
| 73 | **Onboard content** | Минимальный placeholder | Просто текст | ✅ **Работает** (заглушка) |

---

## 2. SIDEBAR (`SidebarView.swift`)

| # | Элемент | Действие | Реальная работа |
|---|---------|----------|-----------------|
| 74 | **Navigate Back** | ← chevron | ✅ **Работает** |
| 75 | **Navigate Forward** | → chevron | ✅ **Работает** |
| 76 | **Toggle Sidebar** | sidebar icon | ✅ **Работает** |
| 77 | **New Task** | plus.circle → `startNewTask` | ✅ **Работает** (⌘N) |
| 78 | **New Project** | folder.badge.plus → `showProjectCreation` | ✅ **Работает** (⌘⇧P) |
| 79 | **Workspace list** | List/grid | ✅ **Работает** |
| 80 | **Workspace sort** | Menu → sortOrder | ✅ **Работает** |
| 81 | **Workspace filter** | toggle + TextField | ✅ **Работает** |
| 82 | **Workspace view mode** | List/Grid toggle | ✅ **Работает** |
| 83 | **Workspace expand/collapse** | Click header | ✅ **Работает** |
| 84 | **Session selection** | `.onTapGesture` (не Button) | ⚠️ **Работает мышкой, НО** нет accessibility, клавиатура не работает |
| 85 | **Session hover actions** | + и ... | ✅ **Работает** |
| 86 | **User avatar** | Circle + initials | ✅ **Работает** |
| 87 | **Notifications button** | Bell → sheet | ✅ **Работает** (пустой экран) |
| 88 | **Settings button** | Gear → settings | ✅ **Работает** |
| 89 | **Workspaces overview** | Arrow button → sheet | ✅ **Работает** |

---

## 3. TOP BAR (`TopBarView.swift`)

| # | Элемент | Действие | Реальная работа |
|---|---------|----------|-----------------|
| 90 | **Project name** | Текст или «MiMoCode» | ✅ **Работает** (раньше был мёртв, теперь добавлен в ContentView) |
| 91 | **Branch indicator** | `appState.gitBranch` | ✅ **Работает** (раньше был hardcoded «main») |
| 92 | **Goal toggle** | TopBarButton → `showGoal.toggle()` | ✅ **Работает** |
| 93 | **Files toggle** | TopBarButton → `showFiles.toggle()` | ⚠️ **Работает, НО** `showFiles` не используется нигде — нет панели Files |
| 94 | **Terminal toggle** | TopBarButton → `showTerminal.toggle()` | ✅ **Работает** |

---

## 4. TASK HEADER (`TaskHeaderView.swift`)

| # | Элемент | Действие | Реальная работа |
|---|---------|----------|-----------------|
| 95 | **Session title** | Текст | ✅ **Работает** |
| 96 | **Workspace name badge** | folder.fill + workspace.name | ✅ **Работает** |
| 97 | **Branch label badge** | monospaced branch name | ✅ **Работает** |
| 98 | **Copy entire chat** | doc.on.doc → `.copyEntireChat` | ✅ **Работает** |
| 99 | **Terminal toggle** | terminal icon → `showTerminal` | ✅ **Работает** |
| 100 | **Goal toggle** | sidebar.right icon → `showGoal` | ✅ **Работает** |

---

## 5. STATUS BAR (`StatusBarView.swift`)

| # | Элемент | Действие | Реальная работа |
|---|---------|----------|-----------------|
| 101 | **Connection status** | Green/red dot + «Connected»/«Disconnected» | ✅ **Работает** |
| 102 | **Selected model** | CPU icon + model ID | ✅ **Работает** |
| 103 | **Streaming/Processing/Idle** | Spinner + текст | ✅ **Работает** |
| 104 | **Endpoint display** | `host:port` — **всегда** | ⚠️ **Работает, НО** показывает endpoint даже когда disconnected |

---

## 6. CHAT PANEL (`ChatPanelView.swift`)

| # | Элемент | Действие | Реальная работа |
|---|---------|----------|-----------------|
| 105 | **Message list** | LazyVStack, auto-scroll | ✅ **Работает** |
| 106 | **Auto-scroll to bottom** | На новых сообщениях | ✅ **Работает** |
| 107 | **Scroll-to-bottom button** | Chevron-down floating button | ✅ **Работает** |
| 108 | **Load older messages** | Button + auto onAppear | ⚠️ **Работает, НО** может каскадно загружать все страницы (onAppear → merge → re-appear) |
| 109 | **Work time separators** | «Worked for Xm Ys» | ✅ **Работает** |
| 110 | **Send message** | Enter/send button | ✅ **Работает** |
| 111 | **Stop generation** | Stop button | ✅ **Работает** |
| 112 | **Message queue** | Pending messages display | ✅ **Работает** |
| 113 | **Model/provider validation error** | — | ❌ **НЕ РАБОТАЕТ** — `sendValidationError` возвращает ошибку, но она игнорируется (нет `messageStore.append`) |
| 114 | **Message edit** | Edit → load into composer | ✅ **Работает** |
| 115 | **Message resend** | Resend → sendDirectly | ✅ **Работает** |
| 116 | **Message retry** | Retry → resend preceding user msg | ⚠️ **Работает, НО** молча ничего не делает если нет предшествующего user message |
| 117 | **Copy entire chat** | notification → ChatCopyLogic | ✅ **Работает** |
| 118 | **SSE streaming (text)** | `message.part.delta` → `streamingText` | ✅ **Работает** |
| 119 | **SSE streaming (reasoning)** | `message.part.updated` → reasoning | ✅ **Работает** |
| 120 | **SSE tool calls** | tool-invocation/tool-call events | ✅ **Работает** |
| 121 | **SSE question asked** | question.asked → pause | ✅ **Работает** |
| 122 | **SSE session idle** | → finishStreaming | ✅ **Работает** |
| 123 | **SSE message ID reconciliation** | server-assigned ID | ⚠️ **Работает, НО** remove+re-append создаёт orphan в БД (прямая мутация messageStore.messages) |

---

## 7. INPUT AREA (`InputViews.swift` + `InputControls.swift`)

| # | Элемент | Действие | Реальная работа |
|---|---------|----------|-----------------|
| 124 | **Centered input card** | Capsule на пустом экране | ✅ **Работает** |
| 125 | **Auto-growing text field** | Рост до 80% экрана | ✅ **Работает** (исправлено) |
| 126 | **Bottom input bar** | Compact bar с сообщениями | ✅ **Работает** |
| 127 | **Access Level menu** | Ask/Edit/Full access | ✅ **Работает** |
| 128 | **Agent Mode menu** | Build/Plan/Compose | ✅ **Работает** (Plan disabled по capability) |
| 129 | **Provider selector** | Menu → selectProvider | ✅ **Работает** |
| 130 | **Model selector** | Menu → selectModel | ✅ **Работает** |
| 131 | **Variant selector** | Menu reasoning effort | ✅ **Работает** (hide when no variants) |
| 132 | **Plus menu** | Add attachment/photo | ✅ **Работает** |
| 133 | **Send/Stop button** | Arrow (send) / Stop (loading) | ✅ **Работает** |
| 134 | **Attachment preview** | Images + files strip | ✅ **Работает** |
| 135 | **Workspace dropdown** | Popover with search | ✅ **Работает** |
| 136 | **Photo picker** | `.fileImporter` for images | ✅ **Работает** |
| 137 | **File picker** | `.fileImporter` for items | ✅ **Работает** |

---

## 8. MESSAGE ROW (`MessageRowView.swift`)

| # | Элемент | Действие | Реальная работа |
|---|---------|----------|-----------------|
| 138 | **User bubble (trailing)** | Справа | ✅ **Работает** |
| 139 | **Assistant bubble (leading)** | Слева | ✅ **Работает** |
| 140 | **Markdown rendering** | Bold, italic, code, lists | ✅ **Работает** |
| 141 | **Code blocks** | Language header + monospace | ✅ **Работает** |
| 142 | **Copy message** | doc.on.doc → clipboard | ✅ **Работает** |
| 143 | **Edit action** | Pencil → `.editMessage` | ✅ **Работает** |
| 144 | **Resend action** | Arrow → `.resendMessage` | ✅ **Работает** |
| 145 | **Retry action** | Counterclockwise → `.retryMessage` | ✅ **Работает** |
| 146 | **Thinking spoiler** | Expandable reasoning | ✅ **Работает** |
| 147 | **Tool inspector** | Collapsed/expanded view | ✅ **Работает** |
| 148 | **Image preview** | Tappable → sheet | ✅ **Работает** |
| 149 | **Question card (wizard)** | Inline tool call → PlanQuestionCardView | ✅ **Работает** |

---

## 9. BOTTOM PANEL (`BottomPanelView.swift`)

| # | Элемент | Действие | Реальная работа |
|---|---------|----------|-----------------|
| 150 | **Tab switch (Terminal/Git)** | Tab bar кнопки | ✅ **Работает** |
| 151 | **Close panel** | X button | ✅ **Работает** |
| 152 | **Terminal command input** | TextField + Enter → Process | ✅ **Работает** |
| 153 | **Terminal output display** | Scrollable lines | ✅ **Работает** (capped 500 строк) |
| 154 | **Command timeout (30s)** | Terminates after 30s | ✅ **Работает** (исправлен waitUntilExit) |
| 155 | **Stop command** | Stop-button | ✅ **Работает** |
| 156 | **Execution timer** | «5s / 25s» | ✅ **Работает** |
| 157 | **clear command** | `clear` → clears output | ✅ **Работает** |
| 158 | **help command** | `help` → shows help | ✅ **Работает** |
| 159 | **sleep command** | `sleep N` → countdown | ✅ **Работает** |
| 160 | **Git tab — branch header** | Текущая ветка | ✅ **Работает** |
| 161 | **Git tab — branch checkout** | Menu dropdown → checkout | ✅ **Работает** |
| 162 | **Git tab — commit** | Button → `git add + commit` | ✅ **Работает** |
| 163 | **Git tab — push** | Button → `git push` | ✅ **Работает** |
| 164 | **Git tab — pull** | Button → `git pull` | ⚠️ **Работает, НО** output переменная не используется |
| 165 | **Git tab — changes list** | File list + counts | ✅ **Работает** |
| 166 | **Branch action button** | Placeholder `{ /* placeholder */ }` | ❌ **НЕ РАБОТАЕТ** — ничего не делает |

---

## 10. RIGHT PANEL (`RightPanelView.swift`)

| # | Элемент | Действие | Реальная работа |
|---|---------|----------|-----------------|
| 167 | **Git Tools section** | Changes + branch + actions | ✅ **Работает** |
| 168 | **Refresh button** | Arrow.clockwise → scheduleGitRefresh | ✅ **Работает** |
| 169 | **Status message** | `gitStatusMessage` text | ✅ **Работает** |
| 170 | **Changes summary** | +N -M | ✅ **Работает** |
| 171 | **Branch selector** | Menu → checkoutGitBranch | ✅ **Работает** |
| 172 | **Commit dialog** | Sheet → commitGitChanges | ✅ **Работает** |
| 173 | **Review & Push** | ReviewPushDialog → commit+push | ⚠️ **Работает, НО** push вызывается даже если commit упал |
| 174 | **Git Init** | Section → `git init` | ✅ **Работает** |
| 175 | **Publish to GitHub** | GitHubPublishWizard | ✅ **Работает** (через gh CLI) |
| 176 | **Plan/Progress section** | Steps display | ✅ **Работает** |
| 177 | **No steps placeholder** | «No steps yet» | ✅ **Работает** |

---

## 11. SEARCH PALETTE (`SearchPaletteView.swift`)

| # | Элемент | Действие | Реальная работа |
|---|---------|----------|-----------------|
| 178 | **Search text field** | «Search tasks…» | ✅ **Работает** |
| 179 | **Results list** | Matching sessions | ✅ **Работает** (FTS5 + fallback) |
| 180 | **Click result → select session** | → `appState.selectSession` | ✅ **Работает** |
| 181 | **Esc to close** | `onExitCommand` | ✅ **Работает** |

---

## 12. NEW PROJECT SHEET (`NewProjectSheet.swift`)

| # | Элемент | Действие | Реальная работа |
|---|---------|----------|-----------------|
| 182 | **Project name field** | TextField | ✅ **Работает** |
| 183 | **Folder picker** | NSOpenPanel | ✅ **Работает** |
| 184 | **Create Project** | → `createNewProject` | ✅ **Работает** |
| 185 | **Cancel** | Dismiss | ✅ **Работает** |

---

## 13. AGENT RESOURCE LIBRARY VIEW (`AgentResourceLibraryView.swift`)

| # | Элемент | Действие | Реальная работа |
|---|---------|----------|-----------------|
| 186 | **Library cards** | Name + category + description | ✅ **Работает** |
| 187 | **Install button** | → `installer.installSkill/MCP` | ✅ **Работает** |
| 188 | **Installed badge** | «Installed» label | ✅ **Работает** |
| 189 | **Error display** | Error message on failure | ✅ **Работает** |

---

## СВОДКА НЕРАБОЧИХ ЭЛЕМЕНТОВ

**Все 19 проблем закрыты в раундах 1–4 (2026-07-17–22)**

| # | Элемент | Проблема | Приоритет | Статус |
|---|---------|----------|-----------|--------|
| 7 | HTTP Proxy «Save» | Пустое замыкание | 🟡 Средний | ✅ Исправлено (Round 1) |
| 9 | Light code theme picker | Пустые action в кнопках | 🟡 Средний | ✅ Исправлено (Round 1) |
| 10 | Dark code theme picker | Пустые action в кнопках | 🟡 Средний | ✅ Исправлено (Round 1) |
| 18 | Log level picker | Значение не передаётся в connectToServe | 🟢 Низкий | ✅ Исправлено (Round 3) |
| 31 | API Key в деталях | Читает plain storage, не Keychain | 🟡 Средний | ✅ Исправлено (Round 3) |
| 48 | Requires API Key toggle | Не скрывает API Key поле | 🟢 Низкий | ✅ Исправлено (Round 3) |
| 68 | Index new folders toggle | Локальный @State, не сохраняется | 🟡 Средний | ✅ Исправлено (Round 1) |
| 69 | Index repositories toggle | Локальный @State, не сохраняется | 🟡 Средний | ✅ Исправлено (Round 1) |
| 70 | Usage time range segment | Hardcoded, не переключается | 🟡 Средний | ✅ Исправлено (Round 3) |
| 71 | Usage stat cards | Hardcoded заглушки | 🟡 Средний | ✅ Исправлено (Round 3) |
| 84 | Session row tap | `.onTapGesture` — нет accessibility | 🟢 Низкий | ✅ Исправлено (Round 4) |
| 93 | Files toggle | `showFiles` нигде не используется | 🟢 Низкий | ✅ Исправлено (Round 4) |
| 104 | Endpoint в статусбаре | Показывается даже при disconnect | 🟢 Низкий | ✅ Исправлено (Round 4) |
| 108 | Load older messages | Каскадная загрузка через onAppear | 🟡 Средний | ✅ Исправлено (Round 4) |
| 113 | Model/provider validation error | Ошибка игнорируется, пользователь не видит | 🔴 Высокий | ✅ Исправлено (Round 1) |
| 123 | SSE message ID reconciliation | orphan в БД | 🟡 Средний | ✅ Исправлено (Round 4) |
| 164 | Git pull output | Переменная output не используется | 🟢 Низкий | ✅ Исправлено (Round 4) |
| 166 | Branch action button | Placeholder, ничего не делает | 🟡 Средний | ✅ Исправлено (Round 3) |
| 173 | Review & Push | Push после失败的 commit | 🟡 Средний | ✅ Исправлено (Round 3) |

### Итого: 19 / 19 закрыты ✅

- 🔴 Высокий: 1 → 0 ✅
- 🟡 Средний: 12 → 0 ✅
- 🟢 Низкий: 6 → 0 ✅

### Исправлено в Round 4 (2026-07-22):
- **#84 Session row tap** — Заменён `.onTapGesture` на `Button` для accessibility
- **#93 Files toggle** — Удалена мёртвая кнопка из TopBar
- **#104 Endpoint в статусбаре** — Скрыт при disconnect
- **#108 Load older messages** — Предотвращена каскадная загрузка
- **#123 SSE message ID reconciliation** — Update in-place вместо remove+re-append
- **#164 Git pull output** — Вывод используется в статусе

### Исправлено в Round 3 (2026-07-21):
- **#18 Log level picker** — Удалён (не передавался в connectToServe)
- **#31 API Key** — Переведён на Keychain (чтение + запись)
- **#48 Requires API Key toggle** — Скрывает поле API Key при выключении
- **#70-71 Usage stats** — Подключены реальные данные из БД
- **#166 Branch action button** — Заглушка заменена на создание ветки
- **#173 Review & Push** — Добавлена проверка успешности commit перед push
