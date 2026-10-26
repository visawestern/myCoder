# Activity 03 — Chat / Composer

Источники: `Sources/Views/ChatPanelView.swift`, `Sources/Views/Components/InputControls.swift`,
`Sources/Views/Components/InputViews.swift`, `Sources/Views/Components/MessageRowView.swift`,
`Sources/Services/MessageStore.swift`, `Sources/Services/SendPersistenceLogic.swift`.

## Control and action inventory

| # | Действие | Trigger → handler → state/persistence → visible result | Ожидаемое поведение | Code quality | Task fit | Runtime status |
|---|---|---|---|---:|---:|---|
| 1 | Text input/Enter | TextField binding → `sendMessage()` → validation/route → `sendDirectly` → message bubble and provider response | Непустой текст sends once; whitespace-only input is ignored | 95/100 | 100/100 | UNVERIFIED — macOS keyboard/runtime required |
| 2 | Send button | idle button → `sendMessage`; loading button → `stopGeneration` → task/SSE/provider abort | Send and Stop are mutually exclusive and do not duplicate a prompt | 95/100 | 100/100 | UNVERIFIED — macOS hit-target/runtime required |
| 3 | Readiness reason | preflight → `SendReadinessLogic` → visible assistant error/rejected-send record | Missing provider/model/connection explains the blocking cause and never silently no-ops | 95/100 | 100/100 | UNVERIFIED — UI rendering required |
| 4 | Provider menu | provider selection → AppState provider mutation → model/variant cascade → composer readiness | Selected provider controls the actual route, not only the label in the composer | 95/100 | 100/100 | UNVERIFIED — macOS menu/runtime required |
| 5 | Model menu | model selection → selected model persistence → route resolver/driver/client | Composer model is the model sent to local, Auto Free, ACP, or browser route | 95/100 | 100/100 | UNVERIFIED — live provider runtime required |
| 6 | Variant/effort menu | variant/effort selection → provider-local state → request options or web injection | Supported controls are visible; unsupported effort is disabled with a reason | 95/100 | 100/100 | UNVERIFIED — native menu and live route required |
| 7 | Access menu | permission selection → `appState.accessLevel` → tool executor/send options | Permission changes affect tool execution and are not merely cosmetic | 95/100 | 100/100 | UNVERIFIED — macOS control/runtime required |
| 8 | Parameters | parameters sheet → `ModelCallParametersStore` → direct/Auto Free/ACP request encoding | Save/reset temperature, tokens, topP and system prompt; selected values reach the route | 95/100 | 100/100 | UNVERIFIED — runtime request capture required |
| 9 | Plus menu and attachments | plus actions → `MessageAttachmentStore` → preview/MessagePartsBuilder → Auto Free content parts/route payload | File/photo/@/#/command actions are discoverable and previews are retained. Images and readable text files reach Auto Free as content parts; unsupported binary files produce a visible warning instead of silent loss | 92/100 | 95/100 | PARTIAL — binary formats remain unsupported by the chat-completions content schema; macOS picker/paste/live request runtime pending |
| 10 | Paste/drop | paste/drop coordinator → attachment store → preview and outgoing parts | Files/images are imported once, previewed, removable, and not duplicated | 90/100 | 95/100 | PARTIAL — native paste/drop runtime pending |
| 11 | Queue | send while loading → `MessageQueue.enqueue` → pending cards/FIFO `processNext` when loading ends | Pending messages remain ordered and visible; user can remove individual entries | 90/100 | 95/100 | UNVERIFIED — runtime timing required |
| 12 | Streaming | provider event/SSE chunks → `MessageStore.update` → streaming bubble/parts/reasoning | Deltas render incrementally; finished response clears loading state | 95/100 | 100/100 | UNVERIFIED — live SSE/provider runtime required |
| 13 | Stop | Stop button/notification → task cancel, SSE disconnect, browser stop, server abort → partial message finalized | Current generation stops, partial content remains, state resets, and status is visible | 92/100 | 95/100 | UNVERIFIED — browser/server/native runtime required |
| 14 | Edit/resend/retry | message action notification → draft extraction or resend queue → send chain | Edit restores text/attachments; resend/retry routes exactly once and preserves context | 92/100 | 100/100 | UNVERIFIED — macOS action menu/runtime required |
| 15 | Copy chat/message | copy action → `ChatCopyLogic`/NSPasteboard → clipboard transcript/text | Copies only available content and does not crash on empty transcript | 90/100 | 95/100 | UNVERIFIED — NSPasteboard runtime required |
| 16 | Markdown/tool calls | message parts → `MessageRow`/tool inspector → rendered markdown, reasoning, tool steps | Formatting and tool state are readable without hiding an empty/error response | 92/100 | 100/100 | UNVERIFIED — visual rendering required |
| 17 | Plan questions | question event → `pendingQuestionRequest`/wizard → `replyToQuestion` → stream resumes or visible error | Answers submit once; loading resumes on success and stops visibly on failure | 92/100 | 100/100 | UNVERIFIED — live server question runtime required |
| 18 | Failed send | readiness/network/route failure → `recordRejectedSend` or assistant update → local session/message persistence → visible error | A failed first send in a workspace creates a project-scoped local session before appending user/error messages; no workspace fails closed without writing to an unrelated DB | 95/100 | 100/100 | CODE/HARNESS VERIFIED; macOS DB/UI runtime pending |

## Round 51 adversarial finding — first-send history was not actually persisted

The prior canonical entry claimed `persistRejectedMessage` and `persistUnsentMessage`, but neither
helper existed in the source. The real chain was unsafe:

1. `sendMessage()` validated the composer and called `sendDirectly`.
2. `sendDirectly` appended `userMessage` while `messageStore.currentSessionID` was nil for a new
   workspace.
3. `MessageStore.append` logged the nil session and skipped `DatabaseBridge.saveMessage`.
4. The standard MiMo Serve branch created its remote session only **after** both the user message
   and empty assistant placeholder had been appended.
5. Preflight failures appended only an assistant error, also with no session, so the first request
   disappeared from local project history after relaunch.

TDD was red first in `SendPersistenceLogicTests`: a new workspace must bootstrap a session before
first append, an existing session must be reused without a duplicate, and no workspace path must
fail closed rather than writing to an unrelated database. The fix adds:

- `SendPersistenceLogic` as a pure contract;
- `AppState.prepareLocalSessionForSend(title:)`, which writes a project-scoped session through
  `DatabaseBridge` and registers it without selecting too early;
- `ChatPanelView.prepareSessionBeforeAppending(route:title:)`, which creates the remote Serve
  session or local project session before the first append;
- explicit `recordRejectedSend`, retaining the user message and visible error on preflight failures;
- a standard Serve branch that reuses the already prepared session instead of creating a duplicate;
- delayed selection until after the first message append, avoiding a SwiftUI session-reload race.

Foundation harness evidence: **88/88 tests passed**, including 3 CHAT-18 tests. Swift parser-only
validation passed for modified macOS source. A full macOS typecheck, SwiftUI/AppKit runtime,
provider/network request capture, and database relaunch test remain unavailable in Linux and are
not claimed as PASS.

## Round 52 attachment fix and remaining boundary

The confirmed Auto Free attachment gap was fixed with a red→green contract. `MyCoderAutoFreeClient.Message`
keeps legacy string content for system prompts, and supports an OpenAI-compatible content array for
user turns. Pasted images and image files become `image_url` data URLs; readable text files become
bounded text parts with filenames; unreadable/binary files produce a visible assistant warning and
are not silently claimed as delivered. The content read is capped at 250,000 characters per file.

The behavior remains **PARTIAL** because the anonymous `/chat/completions` schema does not provide a
portable arbitrary-binary/PDF file part. The UI now tells the user when such a file was not sent,
which is safer than pretending the attachment reached the model. Live OpenCode request capture and
macOS picker/paste runtime are still UNVERIFIED.

## User story

As a user, I can type, send, stream, stop, retry, edit, attach, and copy messages while keeping
provider/model/effort selections coherent. If the provider fails, the first request remains visible
and project-persisted whenever a workspace exists, rather than vanishing because the session was
created too late.

```text
/goal go over every single feature in this file create a user story with expected behaviour based on the code keep a single canonical spreadsheet tracking the features status
• when done switch loop to testing every user story and documenting all errors
• when done fix every logistical or UX error
• test every user behaviour again post fix
```
