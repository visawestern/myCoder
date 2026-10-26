# Activity 05 — Web Login, Sessions and Model Detection

Источники: `WebProvidersSection.swift`, `WebProviderConfig.swift`, `WebProviderConnectivity.swift`,
`WebSessionManager.swift`, `WebModelDiscovery.swift`, `WKWebViewBrowserBridge.swift`,
`MyCoderApp.swift` web browser pool and `ChatPanelView.swift` web send path.

## Full control inventory and chain audit

| # | Действие | Trigger → handler → state/persistence → visible result | Ожидаемое поведение | Code quality | Task fit | Runtime status |
|---:|---|---|---|---:|---:|---|
| 1 | Add Kimi/Qwen/ChatGPT | vendor card → `addVendor` → WebProviderStore upsert → provider card | One config per vendor; no guessed model is inserted | 95/100 | 100/100 | CODE VERIFIED; macOS UI pending |
| 2 | Login unconfigured provider | Login → `beginLogin(newSession:false)` → sheet/default session → WKWebView chat URL | Embedded login opens with the correct vendor URL and default session identity | 92/100 | 100/100 | UNVERIFIED — WebKit/network |
| 3 | Change login | person-arrow action → new UUID/name → login sheet → named session persistence | A second account can be captured without overwriting the first | 95/100 | 100/100 | CODE; WebKit/login pending |
| 4 | Choose saved login | session menu → `activateSession` → active ID/name in WebProviderStore → future browser key | Selecting a named session changes both displayed account and send routing | 95/100 | 100/100 | CODE; native menu pending |
| 5 | Capture authenticated cookies | Capture → WK cookie store → non-empty guard → `WebSessionManager.persist` → metadata/config | Empty cookie snapshot is rejected with an actionable message; valid snapshot becomes active only after disk success | 95/100 | 100/100 | CODE/HARNESS VERIFIED; WebKit cookie runtime pending |
| 6 | Persist failure | cookie callback → `WebSessionManager.persist` throws → red NotificationService error → no active session update | Failed disk write cannot create a false connected provider | 95/100 | 100/100 | CODE path; filesystem runtime pending |
| 7 | Close login sheet | X → dismiss | Close never saves an empty/partial login and does not destroy existing active session | 92/100 | 100/100 | UNVERIFIED — native sheet |
| 8 | Provider connectivity | card status → `WebProviderConnectivity.isConnected` → restore active session, non-empty/non-expired cookies | Added provider is not shown as connected until a usable session exists | 95/100 | 100/100 | CODE; real cookie expiry pending |
| 9 | Remove provider | trash → confirmation → config removal + all session removal + remote mapping clear + selection reconcile | Provider and every named session disappear; active route cannot remain stale | 95/100 | 100/100 | CODE; filesystem/UI pending |
| 10 | Built-in detector status | card label → `WebDetectionStatusLogic` → count from selectable `allModels` | Status names myCoder built-in detection and never claims Auto Free performed it | 95/100 | 100/100 | CODE/HARNESS VERIFIED; visual QA pending |
| 11 | Built-in model detection | Detect models → catalog/custom selector → bridge hydration wait → `discoverAllModels` → capability profiles → store | Reads all valid nested live models, effort and parameter profiles; no AI request is made | 95/100 | 100/100 | CODE; live WebKit DOM pending |
| 12 | AI-assisted detection | Ask myCoder Auto Free → page text → explicit Auto Free stream → strict parse/normalize → non-selectable candidates | Separate optional action; AI candidates are review-only until DOM verification and never enter sendable `allModels` | 95/100 | 100/100 | CODE; WebKit/live Auto Free pending |
| 13 | Detection failure/status | detection task → `DetectResult.failed` → inline status bar | Empty page/selector/no models/errors remain visible and do not erase a previously valid catalog silently | 90/100 | 100/100 | CODE; native visual pending |
| 14 | Show/hide detected models | accordion bar → `showDiscoveredModels` → all rows render | Full-width spoiler shows every detected model, status, effort and parameter badges | 95/100 | 100/100 | UNVERIFIED — macOS hit testing |
| 15 | Select active detected model | active row tap → selectable/active guard → AppState provider/model selection → chat composer | Only active live models can be selected; AI-only/unavailable candidates do nothing | 95/100 | 100/100 | CODE; UI hit testing pending |
| 16 | Remove unavailable candidate | trash on non-active row → discoveredModels removal → onSave/WebProviderStore | Only non-selectable detection residue can be removed; active live models are not exposed as destructive no-op actions | 92/100 | 100/100 | CODE; UI pending |
| 17 | Refresh models from card | refresh icon → AppState `refreshWebModels` → restored session cookies → isolated browser navigate/discover → store reload | Uses the selected named session, replaces stale catalog only with live candidates, and reports errors | 95/100 | 100/100 | CODE; WebKit/live provider pending |
| 18 | Refresh effort/profiles | brain icon → `refreshWebModelsAndEffort` → per-model profiles → store reload/status | Effort is model-specific; unsupported models show no custom effort selector | 95/100 | 100/100 | CODE; WebKit/live provider pending |
| 19 | System prompt templates | Templates menu → config systemPrompt mutation → `onChange` WebProviderStore save → web request | Template selection is visible/editable and clear returns to empty prompt | 92/100 | 100/100 | CODE; visual/live request pending |
| 20 | System prompt editor | TextEditor/Clear → config mutation → save → WebChatDriver request | Manual prompt changes persist and reach only the selected web provider | 92/100 | 100/100 | CODE; live request pending |
| 21 | Tool-call delay | Slider → config `toolCallDelayMs` → save → driver pacing | Bounded 0–3000ms delay is reflected in driver behavior | 92/100 | 100/100 | CODE; live browser timing pending |
| 22 | Keep-alive | Slider → `sessionKeepAliveSec` → save → driver/session reuse | Bounded 30–600s value controls intended session reuse behavior | 90/100 | 100/100 | CODE; live browser timing pending |
| 23 | Browser pool isolation | Chat send → `webView(for:project,chat,provider,session)` → up to 100 keyed WKWebViews → action journal | Projects/chats/accounts cannot share remote page context; LRU cap evicts safely | 95/100 | 100/100 | CODE; macOS WebKit runtime pending |
| 24 | Cookie restore before refresh/send | AppState/ChatPanel → `WebSessionManager.restore` → bridge `setCookies` → navigate | Saved session is actually injected before model discovery and send; failures are visible | 95/100 | 100/100 | CODE; WebKit cookie runtime pending |
| 25 | Remote chat binding after login | web send → local project/chat/session key → verified remote UUID → persisted mapping/journal | Each local chat/session maps to one verified remote chat; wrong host/UUID blocks send | 95/100 | 100/100 | CODE; live WebKit runtime pending |

## Round 54 confirmed defects and fixes

### WEB-LOGIN-11 — empty cookie capture created a false/opaque login state

Capture was available once any page URL existed and passed an empty cookie array to the parent.
That parent persisted an empty store with `try?`, potentially marking metadata active even when the
session could not be restored, while the login sheet gave no actionable reason. Red tests covered
empty/non-empty snapshots, status text, and disk-persistence failure. `WebLoginCaptureLogic` now
rejects empty snapshots. `WebProviderLoginView` leaves the sheet open with an explicit login-required
status, while parent persistence uses `do/catch`, raises a red notification on write failure, and
updates active session metadata only after successful persistence. Targeted tests: **4/4 passed**.

### WEB-LOGIN-12 — built-in detector was misattributed to Auto Free

The provider card said `myCoder Auto Free will detect models` and `myCoder Auto Free detected N
models` even though the normal refresh path uses the built-in DOM detector. This violated the user's
explicit requirement for two separate detection actions. `WebDetectionStatusLogic` now produces
honest myCoder detector text, the header says `Built-in browser detection`, and the second action is
explicitly `Ask myCoder Auto Free`. AI candidates remain non-selectable until verified by DOM
selection. Targeted tests: **2/2 passed**.

## User story

As a user, I can add a web vendor, log into one or more named accounts in the embedded browser,
capture only a real authenticated session, detect all live models with the built-in browser action,
optionally ask myCoder Auto Free for review candidates, and use the selected model in the isolated
project/chat browser route. The app must explain failures and never claim a Linux source check is a
macOS/WebKit runtime pass.

```text
/goal go over every single feature in this file create a user story with expected behaviour based on the code keep a single canonical spreadsheet tracking the features status
• when done switch loop to testing every user story and documenting all errors
• when done fix every logistical or UX error
• test every user behaviour again post fix
```
