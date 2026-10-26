# Activity 06 — Web Chat Driver and Browser Send Chain

Источники: `WebChatDriver.swift`, `BrowserAutomationBridge.swift`, `WKWebViewBrowserBridge.swift`,
`WebToolProtocolEmulator.swift`, `WebToolAccessGate.swift`, `ProjectWebToolExecutor.swift`,
`WebChatEventPresenter.swift`, `ChatPanelView.runWebChatTurn`, `AppState.refreshWebModels` and the
named-session restoration path.

## Full action inventory and chain audit

| # | Действие | Trigger → handler → state/persistence → consumer | Ожидаемое поведение | Code quality | Task fit | Runtime status |
|---:|---|---|---|---:|---:|---|
| 1 | Select web provider | composer provider selection → `selectedProviderID` → `selectedWebProviderConfig` → `sendDirectly` web branch | A `web:<id>` choice routes the message to the matching provider config, not Auto Free or Serve | 95/100 | 100/100 | CODE VERIFIED; macOS UI UNVERIFIED |
| 2 | Resolve model | provider/card selection → `WebProviderStore` selectedModel → `effectiveConfig` in `runWebChatTurn` → driver injection | Composer and browser use one persisted model; stale selections are reconciled before send | 95/100 | 100/100 | CODE/HARNESS; live DOM UNVERIFIED |
| 3 | Inject discovered model | driver → catalog/custom model selector → click menu → exact visible option → success flag | Exact model confirmation is required before typing; missing/unknown model aborts the turn | 96/100 | 100/100 | CODE/HARNESS; WebKit DOM UNVERIFIED |
| 4 | Inject custom model selector | driver → `customModelSelector` fallback when catalog has no `.custom` entry → exact option confirmation | Custom web providers do not silently bypass model selection when a user-provided selector exists | 95/100 | 100/100 | CODE/HARNESS; custom WebKit DOM UNVERIFIED |
| 5 | Inject effort | driver → model-specific availableEfforts → catalog effort selector → exact effort option | Effort is injected only when the selected model supports it; failed required injection blocks send | 95/100 | 100/100 | CODE; live DOM UNVERIFIED |
| 6 | Send prompt | `runWebChatTurn` → isolated WKWebView → `sendMessage` → type + send click | Prompt is typed into the authenticated provider page only after model/effort preflight succeeds | 94/100 | 100/100 | CODE; WebKit/network UNVERIFIED |
| 7 | Restore browser session | named session store → cookies → navigate to target origin → localStorage → reload current URL → readiness poll | Captured cookies and origin storage are applied to the correct vendor page before model discovery or send | 94/100 | 100/100 | CODE/HARNESS; WebKit storage/cookies UNVERIFIED |
| 8 | Await response | send baseline → response text/fingerprint polling → stop-button disappearance + stable non-empty DOM | Old/empty response is never reported as a fresh answer; timeout becomes visible and retryable | 94/100 | 100/100 | CODE/HARNESS; live provider response UNVERIFIED |
| 9 | Stream response | driver `.streaming` → `WebChatEventPresenter`/message mutation → assistant bubble | New response text is visible while generation proceeds; final answer replaces streaming state | 92/100 | 100/100 | CODE; SwiftUI/WebKit rendering UNVERIFIED |
| 10 | Parse tool call | web answer → `WebToolProtocolEmulator.parseToolCalls` → `WebToolCall` → validation/executor | Strict fenced and supported informal tool syntax become canonical calls; unknown syntax is not silently treated as final | 94/100 | 100/100 | Foundation/HARNESS; live model formatting UNVERIFIED |
| 11 | Ask-before-changes gate | driver → `WebToolAccessGate.permission` → `.approvalRequired` event → presenter/chat + action journal | Write/edit/todo/git/task mutations do not execute under `Ask before changes`; the user sees an approval-required status | 95/100 | 100/100 | CODE/HARNESS; native approval UX UNVERIFIED |
| 12 | Execute approved-policy tool | driver → access gate → `ProjectWebToolExecutor` → undo/request_history/filesystem result → `tool_result` | Edit-automatically/full-access policies execute only their permitted operations and feed real results back | 93/100 | 100/100 | CODE; filesystem/process/macOS UNVERIFIED |
| 13 | Tool result loop | executor result → `formatToolResult` → next browser message → next response | The model receives escaped, parseable results and can continue until a final answer | 94/100 | 100/100 | CODE/HARNESS; live model loop UNVERIFIED |
| 14 | Captcha interruption | preflight/poll → `WebSessionLogic.inferState` → screenshot event → presenter status | Captcha is shown in-chat and no further tools/send occur until user action | 92/100 | 100/100 | CODE; WebKit screenshot/captcha UNVERIFIED |
| 15 | Logout interruption | URL/input/page text → `.loggedOut` → visible status → session reset | Expired login is reported as login-required, not as a selector or empty-response failure | 93/100 | 100/100 | CODE/HARNESS; live login page UNVERIFIED |
| 16 | Session-length limit | response markers → `WebSessionLimitLogic` → fresh navigation + carry-over seed → same driver | A provider context limit creates a new remote conversation with explicit carry-over and no silent context mixing | 93/100 | 100/100 | CODE/HARNESS; live provider UNVERIFIED |
| 17 | Remote chat binding | local project/chat/session → verified remote UUID/host → `WebRemoteChatStore` → driver navigation | Each local chat maps to one verified remote chat; wrong host or missing UUID blocks send | 95/100 | 100/100 | CODE; WebKit/network UNVERIFIED |
| 18 | Prompt chunking | oversized prompt → `WebPromptChunker` → numbered parts → final-part marker → sequential sends | Large input is split safely and the model is told not to answer until the final part | 94/100 | 100/100 | Foundation/HARNESS; live provider limits UNVERIFIED |
| 19 | Iteration limit | tool-call loop → `maxToolIterations` → `.iterationLimitReached` → finished visible bubble | Runaway tool loops stop deterministically and report the limit | 94/100 | 100/100 | Foundation/HARNESS; UI rendering UNVERIFIED |
| 20 | Generic/typed error | bridge/executor failure → `.error` or typed event → presenter → assistant bubble | Errors are visible, no false final answer is recorded, and a retry remains possible | 93/100 | 100/100 | CODE/HARNESS; live provider UNVERIFIED |
| 21 | Stop generation | Stop button/notification → `stopGeneration` → vendor stop selector/Escape → loading reset | Stopping ends the browser generation instead of only cancelling Swift tasks | 91/100 | 100/100 | CODE; WebKit hit testing UNVERIFIED |
| 22 | Browser isolation | send/refresh → `webView(for:project,chat,provider,session)` → keyed pool/LRU cap → action journal | Project, local chat, provider and named login cannot share browser context; pool remains capped at 100 | 95/100 | 100/100 | CODE; macOS WKWebView UNVERIFIED |
| 23 | Approval helper contract | generic `requiresApproval` call → tool classification → tests/consumers | Reusable helper classifies all file, git, shell and task mutations consistently with the live gate | 95/100 | 100/100 | Foundation/HARNESS |
| 24 | Completion accounting | driver event → `send_blocked_approval` or `send_completed` → journal/message state | Blocked turns are not labeled successful; completed turns include model/effort/remote metadata | 93/100 | 100/100 | CODE; native journal rendering UNVERIFIED |

## Confirmed defects and TDD fixes in Round 55

### WEB-CHAT-11 — `Ask before changes` did not gate file mutations

`AccessLevel.askBeforeChanges` is presented as “Ask before file changes,” but
`WebToolAccessGate` returned `.allow` for `write_file`, `edit_file` and `todo_write`. The executor
therefore performed real changes immediately. The supposed `requiresApproval` helper was not used by
the driver or executor for these operations, so its existence did not provide a user-visible guard.

Red tests were added first for all three file mutation classes, preserving allowed behavior for
`editAutomatically` and shell gating. The gate now returns `.requireApproval`; `WebChatDriver` emits a
new `.approvalRequired` event before executor dispatch, and `ChatPanelView` records
`send_blocked_approval` rather than `send_completed`. Native approval UI is still UNVERIFIED; the
current safe behavior is to stop and show the actionable status instead of silently mutating files.
Targeted evidence: **3/3 gate tests, 1/1 integration test**.

### WEB-CHAT-12 — the approval event had no presentation/termination chain

Before the fix, even if a lower-level gate result existed, the driver had no dedicated event for the
ChatPanel to render, and the caller could record a successful completion after the driver stopped.
The new event is mapped to persistent chat status, a thread-safe approval signal is consumed by the
caller, and the turn ends as a blocked action. No retry or duplicate remote prompt is created.
Targeted evidence: **1/1 integration test**, full harness included it.

### WEB-CHAT-13 — captured `localStorage` was never captured or restored correctly

`WebSessionStore` had a `localStorage` field and Foundation round-trip tests, but login capture always
constructed `WebSessionStore(cookies: ..., localStorage: [:], ...)`. The first Round 55 implementation
also attempted to call `setLocalStorage` before the page’s target origin was loaded, which cannot
reliably affect the vendor origin. That was caught by red order tests.

The fix captures `localStorage` from the login WKWebView, adds a bridge method with a no-op default
for Foundation fakes, and replays state in the verified sequence `cookies → target navigation →
localStorage → reload current URL`. Model and effort refresh use the same sequence; ChatPanel preserves
an existing remote-chat URL when reloading. Storage replay failures are visible as nonfatal warnings,
while cookie-only sessions remain valid. Targeted evidence: **4/4 restoration tests**.

### WEB-CHAT-14 — custom vendor model selection silently bypassed injection

`WebChatDriver.injectModelAndEffort` returned success when the bundled catalog had no entry. This was
reachable for `.custom`, even when `customModelSelector` was configured, so the selected model was
never confirmed and the prompt was sent under whatever model the page happened to show.

A red test proved that `.custom` must click its persisted selector and confirm the exact option. The
fix uses the custom selector as the primary route, falls back to catalog selectors for supported
vendors, and blocks selected-model sends when neither route exists. Targeted evidence: **1/1 custom
selector test**.

### Approval-helper consistency

The generic `WebToolProtocolEmulator.requiresApproval` helper omitted `edit_file`, `todo_write`,
git mutations and `task`. Red coverage expanded its classification set; the helper now agrees with
the live policy. Targeted evidence: **1/1 helper test**.

## Source-traced controls with no additional confirmed defect

Response baseline/fingerprint handling prevents an unchanged or empty DOM node from being accepted as
a new answer. Captcha/logout checks happen before send and before response read. Session-limit restart,
chunking, bounded iteration, tool validation, project-root path safety, undo/history recording,
remote-chat UUID verification and LRU browser isolation are covered by existing tests or source
contracts. The browser bridge sends DOM events without requiring an active window, but actual
provider-compatible selectors, authentication, model menus, effort menus and response streaming
remain outside Linux verification.

## Canonical user story

As a user, I select a web provider, model and optional effort in the shared composer and send a
message through the authenticated embedded browser. The app must restore the selected named session,
confirm the exact model/effort before typing, preserve project/chat remote context, execute tools only
under the selected access policy, surface captcha/logout/errors, and clearly distinguish blocked,
failed and completed turns. Unsupported macOS/WebKit behavior must be labeled **UNVERIFIED**, never
silently upgraded to a runtime PASS.

```text
/goal go over every single feature in this file create a user story with expected behaviour based on the code keep a single canonical spreadsheet tracking the features status
• when done switch loop to testing every user story and documenting all errors
• when done fix every logistical or UX error
• test every user behaviour again post fix
```

## Evidence and scores

| Check | Result | Boundary |
|---|---:|---|
| WEB-CHAT-11 access-gate tests | **3/3 passed** | Foundation pure policy |
| WEB-CHAT-12 approval interruption | **1/1 passed** | Foundation driver integration |
| WEB-CHAT-13 session restoration | **4/4 passed** | Foundation payload/order contract |
| WEB-CHAT-14 custom selector | **1/1 passed** | Foundation driver integration |
| Approval-helper consistency | **1/1 passed** | Foundation protocol helper |
| Full Foundation harness | **147/147 passed** | Linux-compatible logic and prior contracts |
| Swift parser-only modified-file validation | **passed** | Syntax only; no macOS typecheck |
| Full macOS SwiftUI/AppKit/WebKit build | **UNVERIFIED** | macOS required |
| Live login/cookies/localStorage/DOM/model/effort/response QA | **UNVERIFIED** | macOS, network and provider accounts required |

| Dimension | Before Round 55 | After Round 55 | Evidence |
|---|---:|---:|---|
| Web Chat implementation quality | 74/100 | 95/100 | Four confirmed chain defects fixed; 147/147 harness |
| Web Chat task adherence | 72/100 | 100/100 | Full action inventory, red tests before each confirmed fix |
| Runtime confidence | 0/100 | 0/100 | No macOS/WebKit/live-provider execution |
| Overall verifiable project quality | 96/100 | 97/100 | Full harness, parser and prior source checks |
