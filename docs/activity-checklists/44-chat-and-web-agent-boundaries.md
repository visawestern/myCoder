# Activity 44 — Chat Attachments and Web-Agent Safety Boundaries

## Audit objective

This round audits **CHAT-19** and **WEB-CHAT-11 through WEB-CHAT-15** from composer attachments and history reconstruction through Auto Free payload encoding, web-agent access policy, approval interruption, named-session origin restoration, custom model injection, and complete destructive-tool classification. Every route was traced to its visible result, persistence boundary, and runtime limitation.

## Full chain checklist

| Story | Chain audited | Expected behavior | Result |
|---|---|---|---|
| CHAT-19 | Composer text/files/images → file path/MIME → image data URL or bounded UTF-8 text → unsupported warning → Auto Free message parts → streamed assistant notice | Images reach the anonymous route as `image_url` data URLs; readable files include filename and are bounded; PDF/binary/ unreadable attachments produce visible warnings and are not silently sent. | **Fixed Round 90 for PDF/binary UTF-8 fallback; source/tests green; live request capture UNVERIFIED.** |
| WEB-CHAT-11 | Model tool call → `WebToolAccessGate` → `ProjectWebToolExecutor` → filesystem/shell side effect | Ask before changes blocks every mutation before side effects; edit/full policies allow only their permitted operations; undo/history is recorded for every file/todo mutation. | **Fixed Round 90 for `todo_write` undo/history; source parser green; native filesystem/database runtime UNVERIFIED.** |
| WEB-CHAT-12 | Approval gate → `approvalRequired` event → presenter → turn mutation → ChatPanel status/journal/finish | Blocked mutation is explained in the same assistant bubble; no false completion, automatic retry, or side effect occurs. | **Pass by source/tests; SwiftUI interaction UNVERIFIED.** |
| WEB-CHAT-13 | Named login capture → cookies/localStorage store → send/refresh restore → target-origin navigation → localStorage replay → reload/warnings | Cookie and origin storage restore in deterministic order; optional localStorage failure is visible and does not skip required navigation. | **Pass by source/tests; WKWebView cookie/localStorage runtime UNVERIFIED.** |
| WEB-CHAT-14 | Custom provider config → custom model selector → exact option confirmation → type/send | A custom selector is used when no bundled catalog exists; missing selector or exact option blocks typing and send. | **Pass by source/tests; custom vendor DOM UNVERIFIED.** |
| WEB-CHAT-15 | Tool enum → protocol destructive classification → access gate → executor side effect policy | File, todo, git, shell, and task mutations have identical classification across metadata, gate, driver, and executor. | **Pass by source/tests; live provider/tool runtime not claimed.** |

## Detailed manual trace

| # | Action/function | Chain and expected invariant | Result |
|---:|---|---|---|
| 1 | `autoFreeMessageParts` text | Preserves user text and creates a valid empty text part when no other content exists. | **Pass by source/tests.** |
| 2 | Clipboard images | Nonempty base64 becomes `data:<mime>;base64,<payload>` and then `image_url`; empty data is not sent. | **Pass by source/tests.** |
| 3 | Image files | Reads bytes and sends a data URL; unreadable/empty images produce a visible warning instead of falling through to text. | **Fixed/Pass by source.** |
| 4 | Readable text files | UTF-8 content is bounded to 250,000 characters and preserves filename in encoded text. | **Pass by source.** |
| 5 | PDF/binary files | MIME/extension classifier blocks text fallback and emits explicit unsupported warning. | **Fixed Round 90.** |
| 6 | Auto Free payload encoding | `fileText` encodes as a text part with `[Attached file: name]`; image parts retain `image_url` schema. | **Pass by source/tests.** |
| 7 | Auto Free history | Keeps finished user/assistant turns, removes blank/unfinished assistant placeholders, and bounds history. | **Pass by source/tests.** |
| 8 | Warning presentation | Attachment warnings are prepended to the same assistant bubble during streaming; provider errors remain visible. | **Pass by source.** |
| 9 | `WebToolAccessGate.permission` | Read tools allow; file/todo/git/task mutations require approval at ask-before-changes; shell requires full access. | **Pass by source/tests.** |
| 10 | `ProjectWebToolExecutor.execute` gate | Returns approval before switch execution, so blocked tools cannot touch disk or spawn shell. | **Pass by source/tests.** |
| 11 | `write_file`/`edit_file` | `performFileOperation` snapshots, executes, records undo, and appends request history only after success. | **Pass by source/tests.** |
| 12 | `todo_write` | Validates JSON and required fields, then uses the same transaction wrapper as file mutations. | **Fixed Round 90; macOS executor regression added.** |
| 13 | Approval event | Driver emits `approvalRequired`; presenter renders actionable text; ChatPanel marks the assistant turn blocked and finishes without `send_completed`. | **Pass by source/tests.** |
| 14 | Named session capture | Cookies and localStorage are captured independently and persisted under provider/session identity. | **Pass by source/tests.** |
| 15 | Restoration order | Cookies → navigate target → set localStorage → reload target; optional storage failure is visible. | **Pass by source/tests.** |
| 16 | Custom model selector | Driver uses `customModelSelector` when present; no selector or exact option failure happens before typing. | **Pass by source/tests.** |
| 17 | Destructive classification | `requiresApproval` covers write/edit/todo/git/shell/task and agrees with the access gate. | **Pass by source/tests.** |
| 18 | Native runtime | Actual file undo database, SwiftUI approval display, WKWebView origin state, custom vendor DOM, and live Auto Free request capture require macOS. | **UNVERIFIED.** |

## Confirmed defects and TDD evidence

### CHAT-19 — PDF/binary content could fall through to UTF-8 text

The previous Auto Free attachment path checked image MIME, then attempted UTF-8 decoding for every remaining file. A PDF or binary file whose bytes happened to decode as UTF-8 could therefore be inserted into the text payload instead of receiving the required unsupported-format warning. The red test was written first for PDF, common binary extension, and unknown text extension behavior. The fix adds a deterministic classifier and checks it before UTF-8 fallback; unreadable images now also produce a dedicated warning.

### WEB-CHAT-11/15 — `todo_write` bypassed undo and request history

The access gate correctly classified `todo_write` as mutating, but after approval the executor wrote `.mycoder/todos.json` directly. Unlike `write_file` and `edit_file`, it did not snapshot the prior file, add an undo entry, or append `request_history`. The red macOS regression was written first and requires a successful todo write to create one `todo_write` undo entry, one history row, and to remove the newly created todo file when undone. The fix routes the validated write through `performFileOperation(operation: "todo_write", ...)`.

## Evidence

| Check | Result | Boundary |
|---|---:|---|
| Red CHAT-19 unsupported PDF/binary classifier | **failed as expected** | Classifier absent before fix |
| Green CHAT-19 content suite | **4/4 passed** | Data URL, text file, empty payload, binary classification |
| Red WEB-CHAT todo undo/history regression | **red test added first** | Full executor test requires macOS project DB/runtime |
| Swift parser validation | **passed** | Attachment logic, ChatPanel, executor, gate, protocol, driver, presenter, restoration, and tests |
| Full Foundation harness | **296/296 passed** | Linux-safe suites; macOS-only E09 executor test excluded from harness |
| Adversarial source checks | **12/12 passed** | Injection, retry, AI isolation, compact catalog, and routing invariants |
| `git diff --check` | **passed** | No trailing whitespace |
| Live Auto Free request capture | **UNVERIFIED** | Requires authenticated/active provider and network |
| Native undo/database, SwiftUI approval, WKWebView session, custom DOM | **UNVERIFIED** | Requires macOS runtime |

## Status and scores

`CHAT-19` and `WEB-CHAT-11 through WEB-CHAT-15` remain **PARTIAL** because live provider requests, native filesystem/database undo, SwiftUI approval presentation, WKWebView session restoration, and custom vendor DOM behavior cannot be verified in the Linux Foundation harness. The confirmed source-level attachment and todo-transaction defects are fixed or covered by a macOS-targeted red regression.

| Story | Code quality | Task adherence | Target-runtime confidence |
|---|---:|---:|---:|
| CHAT-19 | 97/100 | 100/100 | 0/100 |
| WEB-CHAT-11 | 97/100 | 100/100 | 0/100 |
| WEB-CHAT-12 | 96/100 | 100/100 | 0/100 |
| WEB-CHAT-13 | 96/100 | 100/100 | 0/100 |
| WEB-CHAT-14 | 96/100 | 100/100 | 0/100 |
| WEB-CHAT-15 | 97/100 | 100/100 | 0/100 |

> A warning is only honest when it is emitted before unsupported bytes enter the payload. A mutating tool is only reversible when its real executor participates in the same undo and history transaction as every other mutation.
