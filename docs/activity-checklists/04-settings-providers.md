# Activity 04 — Settings, Providers and Resources

Источники: `SettingsView.swift`, `GeneralSettingsView.swift`, `ModelSettingsView.swift`,
`ProvidersSettingsView.swift`, `SkillsSettingsView.swift`, `MCPServersSettingsView.swift`,
`PluginsSettingsView.swift`, `CommandsSettingsView.swift`, `StorageSettingsView.swift`,
`UsageSettingsView.swift`, provider/resource services and AppState mutation methods.

## Full control inventory and chain audit

| # | Действие | Trigger → handler → state/persistence → visible result | Ожидаемое поведение | Code quality | Task fit | Runtime status |
|---:|---|---|---|---:|---:|---|
| 1 | Back to workspace | Settings sidebar button → `appState.showSettings = false` → root workspace view | Settings closes without losing current workspace/provider state | 95/100 | 100/100 | UNVERIFIED — macOS window runtime |
| 2 | Settings tab selection | `SettingsTabRow` button → `appState.settingsTab` → `SettingsContent` switch | Every visible tab opens the correct view exactly once | 95/100 | 100/100 | UNVERIFIED — macOS navigation runtime |
| 3 | Theme menu | theme row menu → `appState.appTheme` didSet → defaults/theme palette | Dark/light/system choice persists and updates colors immediately | 95/100 | 100/100 | UNVERIFIED — visual runtime |
| 4 | Language picker | picker → `appState.setLanguage` → AppSettings persistence + localization counter | UI strings refresh and selected language survives relaunch | 95/100 | 100/100 | UNVERIFIED — visual/relaunch runtime |
| 5 | Interface zoom | zoom button → `updateSettings` → AppSettings save → layout/font consumers | One zoom choice is visibly active and persists | 95/100 | 100/100 | UNVERIFIED — visual runtime |
| 6 | Terminal profile inheritance | toggle → settings binding → persisted `inheritTerminalProfile` → terminal consumer | Toggle changes terminal launch/profile behavior, not only label | 92/100 | 100/100 | UNVERIFIED — terminal runtime |
| 7 | Terminal font | text field → AppSettings binding → `TerminalFontResolver` → terminal label/consumer | Invalid/blank input falls back safely and valid font persists | 90/100 | 95/100 | UNVERIFIED — native terminal runtime |
| 8 | HTTP proxy | text field → AppSettings binding → persisted proxy → network clients | Proxy value is retained and used by supported egress paths | 90/100 | 100/100 | UNVERIFIED — network/runtime capture |
| 9 | Input dropdown toggle | toggle → `inputDropdownEnabled` → settings persistence → composer | Dropdown is shown/hidden consistently without disabling text input | 92/100 | 100/100 | UNVERIFIED — composer visual runtime |
| 10 | Code preview theme | theme menu → `updateSettings` → code renderer settings | Light/dark code theme changes preview and persists | 92/100 | 100/100 | UNVERIFIED — visual renderer |
| 11 | Code line numbers/wrapping | toggles → settings bindings → code preview consumer | Preview updates immediately; no unrelated chat layout mutation | 92/100 | 100/100 | UNVERIFIED — visual renderer |
| 12 | Code font size | slider → settings binding → preview consumer | Value remains within 8–24 and visible size changes | 92/100 | 100/100 | UNVERIFIED — visual runtime |
| 13 | Provider category accordion | category header → `collapsedProviderCategories` → provider rows | Full-width accordion opens/closes without changing provider selection | 95/100 | 100/100 | UNVERIFIED — macOS hit testing |
| 14 | Select provider row | direct row click → `selectProvider` → selected provider/model/variant cascade + preference | Provider selection changes the actual send route and detail column | 95/100 | 100/100 | UNVERIFIED — native UI/live provider |
| 15 | Edit custom/web provider | pencil → detail provider ID → endpoint/key/capability editor → `updateCustomProvider` or Web store | Edit opens the selected provider’s fields; Save persists and refreshes models | 92/100 | 100/100 | UNVERIFIED — Keychain/network runtime |
| 16 | Delete custom/web provider | trash → `removeProvider` → config/key/session deletion → selection reconciliation | Mutable provider is deleted; built-in provider has no destructive control; stale selection is avoided | 95/100 | 100/100 | UNVERIFIED — persistence/session runtime |
| 17 | Add provider | Add button → `AddProviderSheet` → validation → `addCustomProvider` → keychain/config/model load | Valid provider is created once; invalid URL cannot be saved | 95/100 | 100/100 | CODE/HARNESS VERIFIED; sheet runtime UNVERIFIED |
| 18 | Test connection | Test button → `ProviderEndpointLogic.modelsURL` → AppState HTTP GET `/models` → result banner | Whitespace/trailing slash is normalized; invalid input fails closed; result is visible | 95/100 | 100/100 | CODE VERIFIED; endpoint/network UNVERIFIED |
| 19 | Provider type change | picker `onChange` → default URL + `defaultRequiresAPIKey` → conditional fields | Switching away from OpenCode Zen restores the new type’s key requirement instead of retaining stale state | 95/100 | 100/100 | CODE/HARNESS VERIFIED; picker runtime UNVERIFIED |
| 20 | Local provider auto-detect | address + Auto Detect → parse/probe → pending confirmation alert → explicit confirm/cancel → LocalProviderLogic save | Detection never adds silently; invalid/non-local addresses are explained | 95/100 | 100/100 | CODE VERIFIED; HTTP/alert runtime UNVERIFIED |
| 21 | Local quick-add | Ollama/OpenCode/Local Agent/ACP card → add guard → UserDefaults save → local provider options | Duplicate kind cannot be added; new card is visible and enabled | 92/100 | 100/100 | UNVERIFIED — native UI |
| 22 | Local enable/disable | row toggle → local config mutation/save → provider options/connectivity | Disabled local provider leaves selectable options and route unavailable | 92/100 | 100/100 | UNVERIFIED — live route |
| 23 | Local model refresh | row refresh → HTTP vendor endpoint → fetched model list → local config persistence → chips | Successful refresh replaces catalog; failure preserves previous models and shows usable state | 92/100 | 100/100 | CODE path; HTTP runtime UNVERIFIED |
| 24 | Local model chip selection | chip tap → catalog validation → select provider if needed → `AppState.selectModel` → defaults | Only active provider’s selected model is marked; tapping a model changes the actual route | 95/100 | 100/100 | CODE/HARNESS VERIFIED; macOS hit-test/runtime UNVERIFIED |
| 25 | myCoder Auto Free catalog refresh | refresh button → `refreshModels` → live catalog/status → selected model reconciliation | Refresh never inserts paid/guessed models and exposes unavailable state | 95/100 | 100/100 | CODE; OpenCode network UNVERIFIED |
| 26 | Auto Free model menu | compact row/menu → store select → AppState selection → route | Current model is shown once; menu switches models; lock remains a separate action | 95/100 | 100/100 | UNVERIFIED — macOS menu/runtime |
| 27 | Auto Free lock/fallback | lock button/toggle → persisted lock → streamChat failover gate/notification | Locked model does not silently switch; unlocked model can fail over with visible error notification | 95/100 | 100/100 | CODE; live provider UNVERIFIED |
| 28 | Auto Free system prompt | TextEditor → `setSystemPrompt` → defaults → system message before user message | Saved prompt is used on every Auto Free request and is visibly editable | 92/100 | 100/100 | CODE; live request capture UNVERIFIED |
| 29 | Model parameters | parameter panel → parse/range validation → `ModelCallParametersStore.set` → route encoding | Invalid values are rejected with a message; reset clears overrides; valid values reach route | 95/100 | 100/100 | CODE; live request capture UNVERIFIED |
| 30 | Skills search/library | search → catalog filter → library cards | Search is trimmed/case-insensitive and no matching state is explained | 95/100 | 100/100 | CODE; bundled catalog/runtime UNVERIFIED |
| 31 | Skill install/update/uninstall | library action → dependency-aware installer → files/registry → `reloadSkills` | Install/update/uninstall changes filesystem and visible button state; errors remain visible | 92/100 | 100/100 | UNVERIFIED — filesystem/native runtime |
| 32 | Skill enable/disable/remove | row button/trash → registry mutation or confirmed directory removal → reload | Disabled skill is not treated as enabled; removal is destructive-confirmed | 95/100 | 100/100 | CODE; filesystem runtime UNVERIFIED |
| 33 | MCP search/library | search → MCP catalog filter → cards | Matching MCP entries are listed without hiding configured servers unexpectedly | 95/100 | 100/100 | CODE; bundled catalog/runtime UNVERIFIED |
| 34 | MCP install/update/uninstall | library action → installer → mcp.json/registry → reload | Server config and registry remain synchronized after every action | 92/100 | 100/100 | UNVERIFIED — filesystem/process runtime |
| 35 | MCP health | row task → cache/registry freshness → max-three probe limiter → health dot | Dot means real health, not merely enabled preference; probe failures do not leave in-flight state stuck | 92/100 | 100/100 | CODE; HTTP/stdio runtime UNVERIFIED |
| 36 | MCP enable/disable/remove | button/confirmation → mcp.json `disabled` + registry → reload | Toggle and remove persist to the actual config; removal is confirmed and visible | 92/100 | 100/100 | UNVERIFIED — filesystem/runtime |
| 37 | Plugin search/list | search → `AgentResourcesLoader.filterEntries` → rows | Plugin list is filterable and state reflects manifest plus user-disabled IDs | 90/100 | 100/100 | CODE; filesystem runtime UNVERIFIED |
| 38 | Plugin enable/disable | row button → `PluginEntry.togglePlugin` → `disabledPlugins` defaults → reload | A visible action toggles the plugin and survives reload; status is not display-only | 95/100 | 100/100 | CODE/HARNESS VERIFIED; filesystem/UI runtime UNVERIFIED |
| 39 | Custom slash command CRUD | New/Edit/Delete → editor/confirmation → `CommandFileManager` → reload/slash registry | Name/template validation prevents empty commands; edit/delete/enable state persists | 95/100 | 100/100 | CODE; native sheet runtime UNVERIFIED |
| 40 | Storage archive/restore | archive/restore buttons → registry mutation → AppState registry refresh → sidebar | Archived rows leave active sidebar; restore returns without relaunch | 95/100 | 100/100 | CODE/HARNESS VERIFIED; macOS/storage runtime UNVERIFIED |
| 41 | Storage deletion | delete-old/delete-archived/reset → distinct confirmations → DB mutation → stats refresh | Destructive scopes cannot cross-trigger; deleted project requires typed name | 95/100 | 100/100 | CODE; DB/native runtime UNVERIFIED |
| 42 | Project relink | orphan Find New Path → NSOpenPanel → registry relink → sidebar/storage refresh | Selected directory is validated/relinked; cancel is a no-op | 90/100 | 100/100 | UNVERIFIED — NSOpenPanel/filesystem |
| 43 | Project compression/backup | VACUUM/export/import buttons → DB/backup logic → stats refresh | Operations target only selected project and leave user files intact | 92/100 | 100/100 | UNVERIFIED — SQLite/native picker |
| 44 | Usage range/filter | segmented range → aggregator filter → cards/table | Range changes all displayed aggregates consistently | 90/100 | 95/100 | CODE; data populated/runtime pending |

## Round 53 confirmed defects and fixes

### SET-11 — local model chips were visually and logically broken

`LocalProviderRow.isSelected` used `config.models.contains(model)`, so every model in the catalog was
styled as selected. Its `selectModel` handler was an empty comment and had no parent callback, so a
chip tap never changed AppState. The red tests covered provider-scoped visual selection, safe catalog
membership, and provider switching. The fix adds `LocalModelSelectionLogic`, wires the row to select
the provider and model through AppState, and reloads the persisted config after refresh to avoid a
stale parent snapshot. Targeted tests: **3/3 passed**.

### SET-12 — provider form endpoints and API-key defaults were unsafe

`testProvider` built `"rawURL/models"`; Add Provider saved raw whitespace/trailing slashes, accepted
missing schemes, and retained `requiresAPIKey = false` after switching away from OpenCode Zen. The
red tests covered canonical URL, `/models` construction, invalid-input rejection, and all key-default
classes. `ProviderEndpointLogic` now validates HTTP(S) host URLs, trims trailing slashes, normalizes
saved name/key/URL, shows invalid URL guidance, and derives API-key defaults on every type change.
Targeted tests: **3/3 passed**.

### SET-13 — plugin state was display-only

The plugin settings page showed Enabled/Disabled but exposed no button, despite promising enable/
disable management. The red tests covered adding/removing disabled IDs and enabled-state derivation.
The fix adds a visible Enable/Disable action, persists through `PluginEntry.togglePlugin`, reloads the
loader state, and factors the mutation into `PluginToggleLogic`. Targeted tests: **3/3 passed**.

## User story

As a user, I can open Settings and manage appearance, providers, model parameters, local/web/Auto
Free routes, skills, MCP servers, plugins, commands, storage and usage. Every destructive action is
confirmed; every mutable selection persists; and unavailable macOS/network/filesystem behavior is
marked UNVERIFIED rather than claimed as a runtime PASS.

```text
/goal go over every single feature in this file create a user story with expected behaviour based on the code keep a single canonical spreadsheet tracking the features status
• when done switch loop to testing every user story and documenting all errors
• when done fix every logistical or UX error
• test every user behaviour again post fix
```
