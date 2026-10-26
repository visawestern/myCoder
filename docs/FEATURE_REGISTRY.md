# myCoder — Canonical Feature Registry

Generated: 2026-07-23 · Updated: 2026-10-23 (F69 direct tool loop + queued inline approvals; plan extended with F71–F75 — 2717 tests, 418 suites)
Source: Full codebase analysis; 2717 executed tests, 418 suites

---

## F01: Chat Message Send
**User Story:** As a user, I type a message and press Enter/Send so the AI agent processes my request and returns a response.
**Expected Behavior:**
- Message is validated (non-empty text, valid model/provider, server connected)
- If no session exists, a new server session is created via `POST /session`
- Message is sent via `POST /session/{id}/message` with parts, agent mode, model, variant
- Assistant response appears in the chat as a streaming message
- Session is selected and stored for follow-up messages
**Status:** ✅ Implemented
**Tests:** MessageSendTests, MessageSendOptionsTests, SessionReuseTests, SessionBusyTests
**Gaps:** ✅ FIXED — Auto-retry on HTTP 409: aborts busy session, waits 500ms, retries send

---

## F02: SSE Streaming
**User Story:** As a user, I see the AI response appear token-by-token as it's generated.
**Expected Behavior:**
- SSE client connects to `http://127.0.0.1:{port}/global/event`
- Events are parsed and dispatched to `handleSSEEvent`
- Assistant message content updates in real-time
- Streaming indicator shows progress
**Status:** ✅ Implemented
**Tests:** SSEClient tests, MessageFlowTests
**Gaps:** None significant

---

## F03: Message Queue
**User Story:** As a user, if I send a message while a response is still generating, my message is queued and sent after the current response completes.
**Expected Behavior:**
- Messages are enqueued when `isLoading == true`
- Next message is processed when current completes
- Queue can be cancelled
**Status:** ✅ Implemented
**Tests:** MessageQueueTests
**Gaps:** Queue only processes next on completion, not on abort

---

## F04: Sidebar — Workspace List
**User Story:** As a user, I see my workspaces (projects) listed in the sidebar, grouped by directory path.
**Expected Behavior:**
- Sessions are grouped into workspaces by normalized directory path
- Each workspace shows its name, session count, and nested session titles
- Sessions are sorted by most recent activity
- Workspace can be selected to filter visible sessions
**Status:** ✅ Implemented
**Tests:** WorkspaceListBuilderTests, SidebarParityTests
**Gaps:** None — hover actions (New task + context menu) implemented in `SidebarView`

---

## F05: Sidebar — Navigation History
**User Story:** As a user, I can navigate back and forward between workspaces I've visited.
**Expected Behavior:**
- Back/forward buttons track workspace selection history
- Buttons are disabled at history bounds
- History is updated on workspace selection (not on programmatic navigation)
**Status:** ✅ Implemented
**Tests:** NavigationHistoryParityTests (in ParityTests)
**Gaps:** None

---

## F06: Sidebar — Search
**User Story:** As a user, I can press Cmd+K to search across all my chat sessions.
**Expected Behavior:**
- Search palette filters sessions by case-insensitive title match
- Results are displayed for selection
**Status:** ✅ Implemented
**Tests:** SearchPaletteLogicTests
**Gaps:** None — Cmd+K opens `SearchPaletteView` sheet wired through `showSearch`

---

## F07: Sidebar — Skills Button
**User Story:** As a user, I click Skills to browse and install agent skills.
**Expected Behavior:**
- Opens settings to Skills tab
- Shows browsable catalog of installable skills
- Install with loading states
**Status:** ✅ Implemented
**Tests:** AgentResourceInstallerTests
**Gaps:** ✅ FIXED — Uninstall support added: `uninstallSkill`/`uninstallMCPServer` + UI "Uninstall" button in library cards

---

## F08: Sidebar — New Task
**User Story:** As a user, I press Cmd+N to start a fresh chat session.
**Expected Behavior:**
- Clears selected session
- Resets message list
- Focuses the message input
**Status:** ✅ Implemented
**Tests:** NewTaskFocusTests
**Gaps:** ✅ FIXED — `startNewTask` bumps `inputFocusRequest`; prompt fields consume it via `makeFirstResponder`

---

## F09: Empty State — Logo and Input
**User Story:** As a user, when no session is selected, I see a centered MiMo logo and input card.
**Expected Behavior:**
- Large MiMo logo watermark
- "Start a new task in {workspace}" text
- Centered input card with workspace chip, prompt, controls
- Input moves to bottom when messages exist
**Status:** ✅ Implemented
**Tests:** InputBarPositionParityTests (in ParityTests)
**Gaps:** None

---

## F10: Input Bar — Workspace Chip
**User Story:** As a user, I see which workspace my message will be sent to.
**Expected Behavior:**
- Chip shows workspace name with folder icon
- Clicking opens workspace dropdown
- Dropdown has search, workspace list, Open folder, Remote connection
**Status:** ✅ Implemented
**Tests:** ParityTests
**Gaps:** Remote connection dialog basic but functional

---

## F11: Input Bar — Model Selector
**User Story:** As a user, I select which AI model to use for my request.
**Expected Behavior:**
- Shows current model name
- Dropdown lists all available models from server providers and custom providers
- Selection persists to UserDefaults
**Status:** ✅ Implemented
**Tests:** ModelSelectorParityTests, ProviderCascadeTests
**Gaps:** None

---

## F12: Input Bar — Agent Mode (Build/Plan/Compose)
**User Story:** As a user, I choose the agent mode to control how the AI approaches my task.
**Expected Behavior:**
- Three modes: Build (code), Plan (reasoning), Compose (writing)
- Mode is sent to server in the request body
- Plan mode requires model capability support
**Status:** ✅ Implemented
**Tests:** AgentMode tests
**Gaps:** Plan mode availability depends on model capabilities

---

## F13: Input Bar — Access Level
**User Story:** As a user, I control whether the AI asks before making changes.
**Expected Behavior:**
- Three levels: Ask before changes, Edit automatically, Full access
- Selection syncs to server via PATCH /global/config
- Selection persists to UserDefaults
**Status:** ✅ Implemented
**Tests:** AccessLevelParityTests
**Gaps:** None

---

## F14: Input Bar — Thinking/Variant Level
**User Story:** As a user, I control the reasoning depth of the AI.
**Expected Behavior:**
- Shows current variant (low/medium/high)
- Dropdown lists available variants based on model capabilities
- Menu hidden when model doesn't support reasoning
**Status:** ✅ Implemented
**Tests:** ProviderCascadeTests
**Gaps:** ✅ FIXED — `variantMenuDisabledReason` now surfaced: menu is shown disabled with tooltip when no variants available, instead of being hidden

---

## F15: Input Bar — Plus Menu
**User Story:** As a user, I click + to add attachments or insert command prefixes.
**Expected Behavior:**
- Menu offers: Add attachment, Add photo, @ file reference, / command, # session
- Add attachment opens file picker
- Add photo opens image picker
- @, /, # insert prefix characters into input
**Status:** ✅ Implemented
**Tests:** PlusMenuTests
**Gaps:** None

---

## F16: Clipboard Paste — Images
**User Story:** As a user, I paste a screenshot or image from clipboard and it attaches to my message.
**Expected Behavior:**
- CmdV in chat input detects image on pasteboard
- Image is converted to base64 and shown as thumbnail preview
- Image is included in message parts when sent
- Supports PNG, TIFF, HEIC, JPEG formats
**Status:** ✅ Implemented
**Tests:** ClipboardImageTests, ClipboardPasteTests, AutomatedClipboardImportTests, PasteboardAttachmentDetectionTests, PasteRoutingIntegrationTests
**Gaps:** None — comprehensive verification documented

---

## F17: Clipboard Paste — Files
**User Story:** As a user, I paste file paths from Finder and they attach to my message.
**Expected Behavior:**
- File URLs from pasteboard are detected and converted to FileInfo
- Files appear in attached files strip
- Files are included in message parts with proper MIME types
**Status:** ✅ Implemented
**Tests:** FileDropTests, PasteRoutingIntegrationTests
**Gaps:** None

---

## F18: Drag and Drop
**User Story:** As a user, I drag files or images from Finder onto the input area.
**Expected Behavior:**
- Drop zone highlights on drag enter
- Files and images are parsed from drop payload
- Added to attachment store
**Status:** ✅ Implemented
**Tests:** FileDropTests
**Gaps:** None

---

## F19: Message Display — Markdown
**User Story:** As a user, I see formatted markdown in AI responses (code blocks, bold, lists, etc.).
**Expected Behavior:**
- Headings, code blocks with language labels, inline code
- Bullet lists, bold, italic, horizontal rules
- Monospace font for code blocks
**Status:** ✅ Implemented
**Tests:** MarkdownTextScaleTests, MarkdownInlineItalicTests
**Gaps:** No syntax highlighting in code blocks. ✅ FIXED — inline italic (`*x*`/`_x_`) parsed; inline parts emitted in source order

---

## F20: Message Display — Reasoning/Thinking
**User Story:** As a user, I can see the AI's reasoning process in a collapsible block.
**Expected Behavior:**
- Reasoning blocks are displayed with distinct styling
- Consecutive thinking-only messages are merged
- Thinking folds into the following reply
**Status:** ✅ Implemented
**Tests:** ReasoningDisplayTests, ThinkingMergeTests
**Gaps:** None

---

## F21: Message Display — Tool Calls
**User Story:** As a user, I see tool call details in expandable inspector cards.
**Expected Behavior:**
- Tool calls show title, arguments, and status
- Expandable inspector with argument sections
- Copy-to-clipboard functionality
**Status:** ✅ Implemented
**Tests:** ToolCallPresentationLogicTests
**Gaps:** None

---

## F22: Message Display — Execution Steps
**User Story:** As a user, I see task execution progress in the right panel Plan section.
**Expected Behavior:**
- Steps sync from server messages into `appState.currentSteps`
- Right panel shows in-progress / completed / waiting states
**Status:** ✅ Implemented
**Tests:** ExecutionStepSyncLogicTests, StepFilterTests
**Gaps:** In-chat step headers not rendered — `groupPartsByExecutionSteps`/`showsStepHeader` helpers are unused by Views (progress lives in the right panel)

---

## F23: Message Display — Spoiler/Expand
**User Story:** As a user, long thinking/reasoning content can be expanded/collapsed.
**Expected Behavior:**
- Thinking content beyond max height is collapsed
- Expand/collapse with spring animation
**Status:** ✅ Implemented
**Tests:** SpoilerExpandLogicTests
**Gaps:** Spoiler applies to thinking blocks only (`ThinkingSpoilerView`); long code blocks are not collapsible

---

## F24: Message Copy
**User Story:** As a user, I can copy individual messages or the entire chat.
**Expected Behavior:**
- Per-message copy button in the message action bar (hover highlights it)
- Copy entire chat generates formatted transcript
**Status:** ✅ Implemented
**Tests:** ChatCopyLogicTests
**Gaps:** None

---

## F25: Message Edit/Retry
**User Story:** As a user, I can edit a sent message or retry a failed response.
**Expected Behavior:**
- Edit button populates composer with original message
- Retry button resends the message
**Status:** ✅ Implemented
**Tests:** MessageEditLogicTests
**Gaps:** None

---

## F26: Message History Pagination
**User Story:** As a user, I scroll up in a long chat to load older messages.
**Expected Behavior:**
- Initial load shows recent 20 messages
- Scrolling to top triggers loading older messages
- Loading indicator shown during fetch
**Status:** ✅ Implemented
**Tests:** MessageStoreTests (pagination cases inside the MessageStore suite)
**Gaps:** None

---

## F27: Plan Question Wizard
**User Story:** As a user, when the AI asks a clarifying question, I answer via a multi-step wizard.
**Expected Behavior:**
- Question displayed as a card with options
- Single/multi-select options
- "Other" text input for custom answers
- Progress indicator for multi-question flows
- Sci-fi themed UI
**Status:** ✅ Implemented
**Tests:** PlanQuestionWizardLogicTests
**Gaps:** None

---

## F28: Git — Status Display
**User Story:** As a user, I see file changes (additions/deletions) in the right panel.
**Expected Behavior:**
- Shows total additions and deletions
- Lists individual changed files with per-file stats
- Refreshes automatically on session change
**Status:** ✅ Implemented
**Tests:** GitRefreshLogicTests, GitRepositoryTests
**Gaps:** None

---

## F29: Git — Branch Management
**User Story:** As a user, I see the current branch and can switch branches.
**Expected Behavior:**
- Shows current branch name
- Dropdown lists all local branches
- Checkout switches branch and refreshes status
**Status:** ✅ Implemented
**Tests:** GitRepositoryTests
**Gaps:** None

---

## F30: Git — Commit
**User Story:** As a user, I commit changes with a message via a premium dialog.
**Expected Behavior:**
- Premium dialog (gradient chrome) offers auto-generate or custom message
- Auto message built by `CommitMessageComposer` from changed files (+adds/-dels), preview shown in dialog
- Stages all changes and commits
**Status:** ✅ Implemented
**Tests:** CommitMessageComposerTests, GitRepositoryTests
**Gaps:** None

---

## F31: Git — Review & Push
**User Story:** As a user, I click "Review & Push", write an optional comment, and get commit + push in one action.
**Expected Behavior:**
- Premium dialog with a comment field and auto summary of pending changes
- Final message = user comment (subject) + auto summary (body); fallbacks when either is empty
- Stages, commits, and pushes in one action; status shown in the panel
**Status:** ✅ Implemented
**Tests:** CommitMessageComposerTests, GitPushUpstreamTests
**Gaps:** ✅ FIXED — push auto-detects missing upstream and runs `push --set-upstream origin <branch>`

---

## F32: Git — Initialize Repository
**User Story:** As a user, I initialize a new git repo from the right panel.
**Expected Behavior:**
- Premium confirmation dialog (no repository-name field — not needed for `git init`)
- Runs `git init` in workspace directory via `GitRepository.run`
- Updates UI to show commit/publish groups
**Status:** ✅ Implemented
**Tests:** GitRepositoryRemoteTests (init path), GitRepositoryTests
**Gaps:** None

---

## F33: Git — Publish to GitHub
**User Story:** As a user, I publish my project to GitHub from scratch via a premium wizard.
**Expected Behavior:**
- Wizard detects GitHub CLI: not installed → offers Homebrew install (or docs link); installed but not signed in → browser sign-in with one-time code shown; ready → publish form
- Publish form asks repo name (pre-filled from workspace name, sanitized) and Public/Private
- Creates repo and pushes via `gh repo create --source=. --remote=origin --push`
- Publish group hidden once an `origin` remote exists
**Status:** ✅ Implemented
**Tests:** GitPublishFlowLogicTests, GitRepositoryRemoteTests
**Gaps:** Homebrew install requires brew present; manual install link offered otherwise

---

## F34: Right Panel — Progress Display
**User Story:** As a user, I see task execution progress in the right panel.
**Expected Behavior:**
- Shows completed, in-progress, and waiting steps
- Collapsed waiting count when > 2 waiting steps
- Updates in real-time as steps complete
**Status:** ✅ Implemented
**Tests:** Screenshot12Tests (RightPanelProgressDisplay), ZCodeFeatureTests (progress model)
**Gaps:** None

---

## F35: Bottom Panel — Terminal
**User Story:** As a user, I open an integrated terminal in the bottom panel.
**Expected Behavior:**
- Tabbed panel with Terminal and Git tabs
- Terminal shows command output
**Status:** ✅ Implemented
**Tests:** None specific
**Gaps:** ✅ FIXED — Real shell execution via Process, output/errors displayed, runs in workspace directory

---

## F36: Settings — General
**User Story:** As a user, I configure theme, language, zoom, and other general settings.
**Expected Behavior:**
- Theme picker (Dark/Light)
- Language picker (English/Russian)
- Zoom level (Smaller/Default/Larger)
- Settings persist to UserDefaults
**Status:** ✅ Implemented
**Tests:** SettingsLightThemeTests, Settings persistence tests
**Gaps:** None

---

## F37: Settings — Code Preview
**User Story:** As a user, I configure code display settings.
**Expected Behavior:**
- Line numbers toggle
- Wrap long lines toggle
- Code font size slider
- Terminal font inheritance
**Status:** ✅ Implemented
**Tests:** Settings tests
**Gaps:** None

---

## F38: Settings — Model Settings
**User Story:** As a user, I manage AI providers and models.
**Expected Behavior:**
- Three-column layout: providers, details, models
- Add/remove custom providers
- Test connection
- Toggle tool calling per provider
- ACP toggle in provider form (protocol client itself — see F44)
- Multiple provider types (OpenAI, Anthropic, Google, etc.)
- Premium empty states for the three cards (icon badge, title, hint, CTA); cards stretch to equal height
- Details card shows model count and the active model chip
- Chat-input selections (provider/model) persist as user preferences: a fallback while a provider is offline never overwrites them, and the preference is restored automatically once the provider reconnects (`SelectionRestoreLogic`)
**Status:** ✅ Implemented
**Tests:** ModelSettingsLayoutLogicTests, ProviderCascadeTests, SettingsProviderLayoutTests, OpenModelAdRemovalTests, ModelSettingsPremiumTests, SelectionRestoreLogicTests
**Gaps:** None. OpenModel advertising fully removed (presets, event links, default-model promotion). Provider-type picker uses a menu (segmented control overflowed the Add Provider sheet); long provider names/URLs truncated.

---

## F39: Settings — Skills Library
**User Story:** As a user, I browse and install agent skills from a catalog.
**Expected Behavior:**
- Searchable catalog of skills
- Install/uninstall with loading states
- Empty state when no skills installed
**Status:** ✅ Implemented
**Tests:** AgentResourceInstallerTests
**Gaps:** None

---

## F40: Settings — MCP Servers
**User Story:** As a user, I manage MCP server configurations.
**Expected Behavior:**
- Load from ~/.mimocode/mcp.json and ~/.cursor/mcp.json
- Display configured servers
- Install MCP servers from the bundled catalog (`AgentResourceLibraryView`)
**Status:** ✅ Implemented
**Tests:** AgentResourceInstallerTests
**Gaps:** No remove/edit UI for existing servers

---

## F41: Settings — Plugins
**User Story:** As a user, I manage installed plugins.
**Expected Behavior:**
- Load from ~/.mimocode/plugins/
- Display plugin list
**Status:** ✅ Implemented
**Tests:** None specific
**Gaps:** Read-only display

---

## F42: Settings — Commands
**User Story:** As a user, I manage custom commands.
**Expected Behavior:**
- Load from ~/.mimocode/commands/ and ~/.cursor/commands/
- Display command list
**Status:** ✅ Implemented
**Tests:** None specific
**Gaps:** Read-only display

---

## F43: Custom Providers — Tool Calling Toggle
**User Story:** As a user, I enable/disable tool calling for custom API providers.
**Expected Behavior:**
- Toggle switch in provider details
- Toggle in add provider dialog
- Respected by ProviderCapabilityGates
**Status:** ✅ Implemented
**Tests:** ProviderCapabilityGates tests
**Gaps:** None

---

## F44: Custom Providers — ACP Protocol
**User Story:** As a user, I enable ACP (Agent Coder Protocol) for compatible providers.
**Expected Behavior:**
- Full ACP client with chat completions, streaming SSE, health check, model listing
- Tool calling and reasoning support
- OpenAI-compatible API format with agent-specific extensions
**Status:** ✅ Implemented — ACP client integrated into send pipeline
**Tests:** ACPClientTests (32 tests — 26 original + 6 routing tests)
**Gaps:** Streaming via ACP not yet supported (non-streaming sendChatCompletion used).

---

## F45: SSE Client
**User Story:** As a user, I receive real-time updates from the server during message processing.
**Expected Behavior:**
- Connects to server SSE endpoint
- Parses event blocks
- Dispatches events to handler
**Status:** ✅ Implemented
**Tests:** SSEClient tests
**Gaps:** None

---

## F46: Session Context Loading
**User Story:** As a user, when I select a session, the right panel and git status update automatically.
**Expected Behavior:**
- Git directory resolved from session/workspace
- Changes loaded from local git and/or server VCS diff
- Right panel shows appropriate content
**Status:** ✅ Implemented
**Tests:** SessionReloadLogicTests, SessionContextLoader tests
**Gaps:** None

---

## F47: Localization
**User Story:** As a user, I see the app in my preferred language (English or Russian).
**Expected Behavior:**
- All UI strings mapped via AppLocalizationKey
- Language switcher in settings
- Persistent language selection
**Status:** ✅ Implemented
**Tests:** AppLocalizationTests
**Gaps:** ✅ FIXED — Right panel strings (Git tools, Branch, Commit, Plan, changes) now localized to EN/RU

---

## F48: Theme System
**User Story:** As a user, I see a consistent sci-fi dark or light theme.
**Expected Behavior:**
- Dark and Light Glass themes
- Consistent color tokens via Color.zcode namespace
- Theme persists to UserDefaults
**Status:** ✅ Implemented
**Tests:** LightThemeContrastTests, SettingsLightThemeTests
**Gaps:** None

---

## F49: Typography Scaling
**User Story:** As a user, I can adjust the app's zoom level for readability.
**Expected Behavior:**
- Three zoom levels: Smaller, Default, Larger
- All UI elements scale via interfaceFont modifier
- Layout dimensions adjust proportionally
**Status:** ✅ Implemented
**Tests:** InterfaceTypographyTests, MarkdownTextScaleTests
**Gaps:** None

---

## F50: Provider Selection Cascade
**User Story:** As a user, when I switch providers, the model and variant are updated intelligently.
**Expected Behavior:**
- If current model exists in new provider, it's kept
- Otherwise, first available model is selected
- Variant is normalized to available options
- Plan mode fallback if capabilities don't support it
**Status:** ✅ Implemented
**Tests:** ProviderCascadeTests, ProviderSelectionLogic tests
**Gaps:** None

---

## F51: Stop Generation
**User Story:** As a user, I can stop an in-progress AI response.
**Expected Behavior:**
- Stop button appears during streaming
- Clicking cancels the request, disconnects SSE, aborts server session
- UI shows "Generation stopped" when content was empty
- Partial content preserved when available
- Idempotent — multiple stop calls safe
**Status:** ✅ Implemented
**Tests:** StopGenerationFlowTests (28 tests)
**Gaps:** None — full abort flow test coverage including task cancellation, SSE disconnect, queue cancel, notification integration

---

## F52: Server Connection Management
**User Story:** As a user, I connect to a MiMo Serve instance and see its status.
**Expected Behavior:**
- Auto-connects to localhost:4096
- Connection status shown in status bar (green/red)
- Remote connection dialog for custom host/port
- Models and providers loaded from server
**Status:** ✅ Implemented
**Tests:** AppStateServerTests, LiveIntegrationTests
**Gaps:** None

---

## F53: Status Bar
**User Story:** As a user, I see connection status, model name, and streaming progress at the bottom.
**Expected Behavior:**
- Green/red connection indicator
- Selected model name
- Streaming/loading indicator
- Active session info
**Status:** ✅ Implemented
**Tests:** "Status Bar" suite in MessageFlowTests (string helpers only, not the view)
**Gaps:** None

---

## F54: Task Header
**User Story:** As a user, I see session title, workspace, branch, and action buttons in the header.
**Expected Behavior:**
- Session title display
- Workspace and branch chips
- Toggle buttons: right panel (goal), terminal, sidebar
**Status:** ✅ Implemented
**Tests:** TaskHeaderTests
**Gaps:** No dedicated files/git/settings toggles in the header; `showGoal` opens `RightPanelView` (git + plan), not a separate goal panel

---

## F55: Goal Panel
**User Story:** As a user, I manage project goals and task lists in the right panel.
**Expected Behavior:**
- `showGoal` opens `RightPanelView` (Plan/progress + Git tools) — this is the goal surface
**Status:** ✅ Resolved — dead `GoalPanelView` removed; right panel Plan section is the goal/progress UI
**Tests:** DeadCodeRemovalTests
**Gaps:** None

---

## F56: Image Preview
**User Story:** As a user, I click an image in the chat to see it full-size.
**Expected Behavior:**
- Thumbnail in message row
- Click opens full-size preview sheet
- Preview can be dismissed
**Status:** ✅ Implemented
**Tests:** MessageDisplayImageTests
**Gaps:** None

---

## F57: Attached Images Strip
**User Story:** As a user, I see thumbnails of images attached to my message before sending.
**Expected Behavior:**
- Horizontal scrollable strip of image thumbnails
- Each thumbnail has a remove button
- Count shown in toolbar
**Status:** ✅ Implemented
**Tests:** ClipboardImageTests
**Gaps:** None

---

## F58: Workspaces Overview
**User Story:** As a user, I can view all workspaces in an overview mode.
**Expected Behavior:**
- Grid or list view of all workspaces
- Sorting by name, recent use, task count
- Filtering by name search and session count presence
- Session count filter presets: All / Has sessions / Empty
**Status:** ✅ Implemented
**Tests:** SidebarWorkspaceLogicTests (17 tests)
**Gaps:** None — full sort/filter implementation with combined name + session filtering

---

## F59: Notifications
**User Story:** As a user, I see notifications about completed tasks or updates.
**Expected Behavior:**
- Bell icon with unread badge count in sidebar
- Notification sheet with real notification list sorted by time
- Mark as read / Mark all read / Remove / Clear all
- Notification types: info, success, warning, error with appropriate icons
- Auto-generated on: task complete, generation stopped, server connect/disconnect, git operations, session busy
- Notification actions: open session, open settings, view git changes
- Max 50 notifications, auto-pruning
**Status:** ✅ Implemented
**Tests:** NotificationServiceTests (24 tests)
**Gaps:** ✅ FIXED — `taskCompleted()` trigger was dead code, now wired in `ChatPanelView.sendDirectly()` after successful message completion

---

## F60: User Profile
**User Story:** As a user, I see my avatar and name in the sidebar.
**Expected Behavior:**
- Avatar with initials
- Display name (from `NSFullUserName()` via `UserProfileDisplay`)
**Status:** ✅ Implemented (display only)
**Tests:** None
**Gaps:** Avatar/name are non-interactive; no profile menu or management

---

## F61: Undo File Operations (Keyboard Shortcut)
**User Story:** As a user, I press Cmd+Option+Z to undo the last file change made by the AI.
**Expected Behavior:**
- Cmd+Option+Z triggers `UndoRedoManager.shared.undo(sessionId:)`
- Restores file from snapshot taken before AI modification
- Menu item "Actions > Undo Last File Change" in app menu bar
- Disabled when no session is active
**Status:** ✅ Implemented
**Tests:** None — manual verification only
**Gaps:** Redo (Cmd+Shift+Z) not yet implemented in UndoRedoManager; only Undo is wired. Standard text field undo (Cmd+Z) remains separate and unaffected.

---

## F62: Session Row Actions (Rename / Share / Export / Archive / Delete)
**User Story:** As a user, I right-click a chat and rename, share, export, archive or delete it without losing messages.
**Expected Behavior:**
- Ellipsis menu on every session row: Rename…, Share, Export Transcript…, Show in Finder (real folders only), New Task, Archive, Delete…
- Rename switches the row to an inline TextField with autofocus, Enter/save button, Esc/xmark cancel, and commit on focus loss
- Rename/delete persist through the owning store (global DB or project DB); a stale id reports failure and surfaces an error notice instead of a fake success
- Delete asks for confirmation and removes dependents explicitly (SQLite FKs are OFF by default)
- Export writes a Markdown transcript through NSSavePanel
**Status:** ⚠️ Partially Implemented
**Tests:** SessionTranscriptLogicTests (4), ProjectDatabaseManagerTests.renameAndDeleteSession, DatabaseManagerMaintenanceTests.renameSessionUpdatesTitle, DatabaseBridgeSessionActionsTests (1); full suite 2616 GREEN
**Gaps:** Server-backed (mimo serve) chats are removed locally only; there is no remote DELETE or tombstone yet. Live click-through of the rename commit was interrupted by the macOS lock screen; DB persistence is covered by tests.

---

## F63: Context Usage Meter and Compaction
**User Story:** As a user, I see how much of the context window a chat consumes and can compact it before the provider truncates it.
**Expected Behavior:**
- Badge shows estimated usage against the catalog window with warning/critical states
- `/compact` and auto-compaction summarize the conversation, persist a summary message, and truncate model history at the last summary while the visible chat stays complete
- Only local providers are eligible; server routes receive an honest "not available" notice
- Short conversations get "still short — nothing to compact yet" instead of a fake summary
**Status:** ⚠️ Partially Implemented
**Tests:** ContextUsageLogicTests, ConversationCompactionLogicTests, ConversationSummarizer tests
**Gaps:** Live success path unverified in this install: the free tier is rejected upstream and no other provider is configured. The routing/notice path was verified live.

---

## F64: Spec-First Project Wizard
**User Story:** As a user, I create a project through a wizard, answer the planner's questions, and get a versioned specification plus an atomic decomposition before any code is written.
**Expected Behavior:**
- Sidebar New Project is a dropdown: Empty project or Project with wizard
- Wizard projects block chat until the spec is ready or the user force-finishes
- Setup stores planner/coder roles and the project brief; checklist is derived from real data, never fake progress
- Interview responses are parsed from planner JSON (fenced/prose-wrapped JSON accepted); malformed or empty questions are rejected
- The planner service maps the selected OpenAI-compatible, OpenCode serve or Auto Free route; unsupported web/ACP/MiMo serve routes fail with an explicit error instead of silently switching transport
- Decomposition validates unique keys, dependencies, acyclicity and acceptance criteria; execution selects exactly one ready node at a time
- TZ revisions are append-only and versioned by the store; requirements, nodes, edges, history and node sessions persist in `spec_*` project tables
- A new TZ revision starts with an empty decomposition; older revisions and their nodes remain readable
- The planner receives a bounded, deterministic snapshot of the existing repository (tree + key manifests, secrets and dependency folders excluded)
- Wizard labels and every planner-generated string follow the language selected in settings; internal jargon (planner/coder/atomic decomposition) stays out of user-facing copy
- Planner calls use a long background timeout (600s transport, 660s action) so free local models can finish large specifications without losing a turn
- Per-node coding starts the next runnable task in a dedicated, linked chat and sends a spec-grounded prompt only after that chat's history has loaded
- Exactly one task runs at a time; pending dependencies block, done/skipped unlock dependents, and failed/blocked tasks require an explicit Retry
- Verification is manual: the user marks the running task done/failed and can reopen its coding chat; the top-bar Tasks button reopens the board after setup
- The task board is offered only for projects that actually have a wizard draft, so empty projects are never converted by a stray click
**Status:** ✅ Implemented
**Tests:** SpecWizardDraftTests (6), SpecPlannerLogicTests (12), SpecSchemaTests (3), ProjectSpecStoreTests (7), SpecPlannerServiceTests (9), SpecWizardSessionTests (9), SpecContextBuilderTests (4), AppActionRouterTests (4), SpecNodeExecutionLogicTests (11), SpecNodePromptFlushLogicTests (8); full suite 2705 GREEN
**Gaps:** Per-node verification is a deliberate manual done/failed decision, not an automated verifier. The wizard cannot use web, ACP or MiMo serve providers as its planner; it reports that clearly. Live E2E through the local action API is verified end-to-end (Russian interview, 18.9k-char TZ, 14-node acyclic graph, node status/link, finish and restart persistence). Per-node coding N1–N5 ran with gemma4:31b-cloud; N4 was re-run directly through `ollama-local` after the direct tool loop landed, and `swift test` stayed green (6 tests). Earlier N1–N3/N5 runs used a temporary local OpenCode server before direct tool execution existed. Live AX click-through still needs Accessibility permission.

---

## F65: Reasoning Spoiler Turn Grouping
**User Story:** As a user, I want every reasoning chunk that belongs to one answer under a single Thinking spoiler instead of several detached spoilers.
**Expected Behavior:**
- Reasoning from all assistant messages in one user turn is merged into the first assistant message of that turn
- Later tool-round messages lose their own spoilers; user messages still start a new turn and a new spoiler
- Duplicate chunks (reasoning channel + `.reasoning` part) appear once
- While a message is still streaming, its live reasoning stays in the streaming bubble so the spoiler cannot collapse mid-turn
- The collapsed preview is clipped from the top, so it shows the first lines instead of a mid-text slice
- The live assistant placeholder keeps its local ID; the server ID is stored only for reconciliation, so SSE updates and the final `finish` reach the same message
**Status:** ✅ Implemented
**Tests:** ReasoningSpoilerGroupingTests (5); SessionReuseTests (assistant update key, 1)
**Gaps:** None.

---

## F66: User Message Navigator
**User Story:** As a user with a long chat, I want a small fixed navigator on the right so I can jump straight to any of my own messages instead of scrolling.
**Expected Behavior:**
- Floating vertical rail pinned to the trailing edge, vertically centered like the scroll-to-bottom button and not blocking the chat
- One small numbered button per user message, scrollable when the list is taller than 280 pt
- Clicking a button scrolls that message to the top of the viewport
- Hovering a button shows a tooltip with the first 100 characters of the message, whitespace-normalized
- Attachment-only user messages remain navigable and preview their file names
- Empty assistant/system messages never appear in the rail
**Status:** ✅ Implemented
**Tests:** UserMessageNavigatorLogicTests (7)
**Gaps:** None.

---

## F67: Chat Loading Indicator
**User Story:** As a user, I want to see that a chat is loading instead of an empty screen, so I know whether my history is on its way.
**Expected Behavior:**
- While a session's history is loading, a centered spinner and "Loading chat…" replace the empty-state logo/title in the chat body
- A same-session refresh keeps the messages visible and shows a slim inline spinner above them
- The loader is keyed to the session that started the load; a slow superseded load cannot clear the loader of the newly selected chat
- The loader is localized for every supported language
- Parallel test execution cannot corrupt process-wide slash-command usage history (NSLock around record/read/reset)
**Status:** ✅ Implemented
**Tests:** ChatLoadingIndicatorLogicTests (3); SlashCommandRegistryTests (concurrent usage, 1)
**Gaps:** None.

---

## F68: OpenCode Custom Provider Routing
**User Story:** As a user running an OpenCode server with a custom provider (for example Ollama/Gemma), I can select that server in the app and have the server execute tools with the selected model instead of always using the built-in `opencode` provider.
**Expected Behavior:**
- A local OpenCode provider persists an `openCodeProviderID` (default `opencode`; legacy configs decode safely)
- Model refresh for that provider is scoped to its configured server provider, so a custom non-free provider is not replaced by the built-in free list
- Chat sends (blocking and SSE) pass the configured provider id to `POST /session/:id/message`
- The spec planner on the same route carries the provider id too, so interview/spec calls do not fall back to the built-in provider
- Other local kinds (Ollama, generic OpenAI-compatible, local agent, ACP) are unchanged
**Status:** ✅ Implemented
**Tests:** OpenCodeServeClientTests (message body, send, stream), LocalProviderConfigTests (legacy default, custom round-trip), ProviderAutoDetectorTests (custom server provider scoping), SpecPlannerServiceTests (route carries provider id), SendRoutingTests (OpenCode route); full suite 2705 GREEN
**Gaps:** This routing is optional: direct Ollama/OpenAI-compatible providers now execute tools themselves (F69), so an OpenCode server is only needed when the user wants its provider/session features.

---

## F69: Direct Local Model Tool Loop
**User Story:** As a user running Ollama locally, I want the selected model to actually edit files and run commands in my project, not just print tool-call text.
**Expected Behavior:**
- Direct `.ollama` / `.openAICompatible` sends attach the tool-protocol preamble and run an agentic loop (up to 15 iterations)
- Tool blocks are parsed with the existing `WebToolProtocolEmulator`, validated against the project root, and executed by `ProjectWebToolExecutor`
- Results are fed back to the model; tool call parts stay on the assistant message for the UI
- Final text and usage persist on the assistant message; transport errors surface as an explicit local-model error
- Access level is enforced by the executor: Full access runs commands, Ask returns an approval-required message
**Status:** ✅ Implemented
**Tests:** WebProviderTests (tool protocol parser/preamble, 10+); WebToolApprovalDetailsTests (7); ToolApprovalCenterTests (5); full suite 2717 GREEN (418 suites); live E2E: `gemma4:31b-cloud` via `ollama-local` created `ollama-direct-ok.txt` with `write_file` and read it back; S7 N4 ran `swift test` directly and reported 6 passing tests
**Gaps:** Pending approvals are process-memory by design: the suspended turn cannot survive an app restart. Notifications are in-app with a sound; no macOS Notification Center delivery yet.

---

## F70: Image Response Collage + Searchable Metadata
**User Story:** As a user, when a model answer contains one or more images, I want to see them as a compact collage and later find them by their content, instead of scrolling a raw list of links.
**Expected Behavior:**
- Detect every image in a model response (markdown images, direct URLs, attachments/base64) without dropping or rewriting the text around it
- Render one primary image with a thumbnail strip beneath it; clicking/tapping a thumbnail switches the primary image
- Keep the collage responsive, keyboard-accessible and honest on load failure (broken-image state, no fake placeholder)
- Persist each image with its message and metadata: title, description, type/format, dimensions, source URL, model/provider and timestamps
- Make that metadata searchable locally and restore the collage after session reload
- Optionally caption/tag images with a local vision model when metadata is missing; a failed caption run leaves the image usable and records the failure
**Status:** ❌ Not Implemented (planned)
**Tests:** None yet
**Gaps:** Needs an image storage schema/cache, URL downloader with limits, collage UI, metadata search, and a local vision-model adapter.

---

## F71: Sidebar Tree — Stable Ordering, Pinning, Project-less Chats
**User Story:** As a user, I want the sidebar to be one deterministic tree where every chat has exactly one parent, project-less chats sit as their own rows with a distinct icon, and opening a chat does not reshuffle the list.
**Expected Behavior:**
- A single tree builder classifies every session once: standalone chats → project-less top-level rows (chat icon), project sessions → that project's children; no session appears twice or jumps between sections
- Project children load from that project's own database, not from the currently loaded project only
- Opening a chat must not bump its `updated_at` — only real activity (new/edited messages) moves a chat to the top
- Projects can be pinned with a pin affordance and pinned projects always sort first
- The Group/Project toggle and the duplicated sidebar-collapse button are removed; the remaining toolbar controls move up into the freed space
- Explicit "show all" instead of silently truncating children to twelve
**Status:** ❌ Not Implemented (planned)
**Tests:** None yet
**Gaps:** Needs `SidebarTreeBuilder`, a pinned-projects store, an `unarchiveSession` fix that stops touching `updated_at` for non-archived rows, and removal of `SidebarGroupingMode`/`SidebarGroupingPill`.

---

## F72: Chat Scroll Position & Auto-scroll Gate
**User Story:** As a user reading chat history, I want the view to stay where I left it — auto-scrolling only when the chat is exactly at the bottom, and my position restored when I come back to a chat.
**Expected Behavior:**
- Bottom detection uses the real scroll offset (`bottomGap`), not "is the 1pt sentinel visible"
- Auto-scroll runs only when `bottomGap <= 0.5pt`; scrolling up by even 1pt disables it immediately
- The gate is re-checked inside the deferred scroll closure (no scroll-through race)
- Each chat remembers its last scroll position; switching to a chat restores it, or scrolls to the end when no position was stored
- Scroll-to-bottom button and history pruning follow the same bottom state
**Status:** ❌ Not Implemented (planned)
**Tests:** None yet
**Gaps:** Needs `NSScrollView` introspection, an offset-based `ChatScrollLogic` predicate and a per-session scroll-position store.

---

## F73: Status Panel (replaces the mislabelled "Goal" panel)
**User Story:** As a user, I want the right panel to be a status overview — git, plan, running processes and terminals — that never opens by itself.
**Expected Behavior:**
- The panel opens only from its own button; switching chats, `todowrite`, `step-start` and step syncing never open it
- The tab is labelled "Status" instead of "Goal" (the panel never contained a goal)
- Sections: git status/branch/commit, plan & running steps, running processes, terminals
- The terminal's running-command state moves out of the view into shared app state so the status is visible without opening the bottom panel
- API action renamed to `app.status.toggle` (old `app.goal.toggle` kept as an alias)
**Status:** ❌ Not Implemented (planned)
**Tests:** None yet
**Gaps:** Needs the `showGoal` → `showStatusPanel` rename, removal of `SessionContextLoader.shouldOpenRightPanel`, new localization key and shared running-command state.

---

## F74: Reasoning & Tool-call Spoiler Adjacency
**User Story:** As a user, I want reasoning and tool calls grouped only when nothing sits between them, so the order of decisions stays visible.
**Expected Behavior:**
- Every assistant turn keeps one ordered timeline (`Message.parts` is the source of truth) in all paths: direct local, Auto Free, web driver, remote Serve
- Consecutive reasoning runs merge into one spoiler; text, a tool call or an image between them splits them into separate spoilers
- Consecutive tool calls merge into one spoiler (already the case) and keep their arrival order
- The answer bubble no longer renders before earlier tool spoilers
- Turn-level reasoning consolidation that reorders content is removed
**Status:** ❌ Not Implemented (planned)
**Tests:** None yet
**Gaps:** Needs a `.reasoning` segment case, reasoning parts appended in every path, and removal of the turn-based consolidation/hoisting.

---

## F75: Tool Inspector — Resizable List, Wrapped Output, Terminal Colors
**User Story:** As a user inspecting tool calls, I want to resize the command list, read long arguments and results with wrapping and a font size I choose, and see terminal colors.
**Expected Behavior:**
- The step list column is resizable by dragging its divider (clamped, persisted)
- Arguments and results wrap by line instead of scrolling horizontally, with an optional wrap toggle
- Font size for arguments/results is adjustable (buttons and ⌘±) and persisted
- ANSI SGR sequences in command output are rendered with terminal colors and bold/reset handling
**Status:** ❌ Not Implemented (planned)
**Tests:** None yet
**Gaps:** Needs `ToolInspectorLayoutLogic`, an `AnsiSGRParser` and a terminal-styled text view; no ANSI helper exists in the codebase today.

---

## Summary

| Status | Count |
|--------|-------|
| ✅ Fully Implemented | 67 |
| ⚠️ Partially Implemented | 2 |
| ❌ Not Implemented | 6 |
| **Total Features** | **75** |

---

## Priority Improvement Candidates

67 fully implemented, 2 partially implemented, 6 planned. Remaining polish items:
- ACP streaming support (non-streaming sendChatCompletion integrated)
- Localization of settings views (~75 strings in 8 tabs)
- UndoRedoManager redo support (Cmd+Shift+Z)
- Remote delete/tombstone for server-backed chats
- Live compaction verification once a working provider is configured
- F70 image-response collage, searchable image metadata and optional local vision captions
- F71 sidebar tree, stable ordering and pinned projects
- F72 chat scroll position memory and strict auto-scroll gate
- F73 status panel replacing the mislabelled "Goal" panel
- F74 reasoning/tool-call spoiler adjacency with a preserved decision order
- F75 resizable tool list, wrapped output and ANSI terminal colors
- F76 chat navigator up/down buttons and current-message highlight (done 2026-10-24)
- F77 LaTeX math markdown rendering for gemma-style $..$/$$..$$ output (done 2026-10-24)
- F78 fix the missing tail chunk of the last dialog on open (done 2026-10-24: durable session→project route, discovery across registered projects, recovery of a tail stranded in the global store)
- F79 sliding chat window: unload oldest rows as new messages arrive, reload upward on scroll
