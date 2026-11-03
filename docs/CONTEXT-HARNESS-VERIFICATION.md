# Context harness verification — 2026-11-03–04

Checkpoint of all initial project changes: `d5d1529`, pushed to `origin/main`; working tree confirmed clean immediately afterwards. Further changes below implement the follow-up instructions and verification endpoints.

## Current checks

| Check | Result | Evidence |
|---|---|---|
| Full unit gate before app build | PASS, exit 0: 55 XCTest + 3369 Swift Testing | `verification/2026-11-04/unit-summary.txt`; `/tmp/mycoder-full-gate.log` |
| Context task instructions and tool descriptions | TDD RED → GREEN | `TaskInstructionDeliveryTests`, `LocalTaskInstructionTests`, `ToolInstructionGuideTests` |
| Invalid browser API request cannot launch engine | PASS | `BrowserFetchAPILogicTests` |
| Native test-window lifecycle | TDD RED → GREEN, 17 XCTest | `/tmp/mycoder-window-lifecycle-green.log` |
| Markdown palette/cache consistency | TDD RED → GREEN, 20 tests | `/tmp/mycoder-markdown-theme-green.log` |
| Application bundle | BUILD RUNNING | `/tmp/mycoder-app-build-final.log` |
| Live context API / persisted user turn | NOT RUN YET | Run after bundle is built |
| Live provider login pages / hidden window / focus | NOT RUN YET | Run after bundle is built |
| Live browser.fetch: text / JavaScript / click / PNG / public search | NOT RUN YET | Run after bundle is built |
| Context tabs / raw toggle UI | NOT RUN YET | App UI API + window capture |

The default test run skips 14 opt-in live tests in 4 suites (serve, local/direct providers, clipboard, plus the opt-in browser test). A default unit PASS is not a live browser/provider PASS.

## Delivered behavior

- Each project turn retrieves context, including the first turn. No lexical code match retains available history, project rules and known gaps.
- The assigned internal model selects validated files/symbols/memory tags/installed skills, asks additional dependency questions and proposes bounded task-specific procedures. The main model receives these procedures as recommendations subordinate to the user request and project rules.
- A bounded static graph includes incoming and outgoing relationships, confidence, same-file dependencies and explicit coverage limits. Missing graph evidence triggers investigation questions about UI/settings, persistence/migrations/export, tests and documentation.
- Actual host tools are documented with descriptions, argument schemas, examples, execution/result protocol, permissions and availability limits. Native transports continue using their native tool interface.
- Stored outgoing context is inspectable in grouped instruction/task/dialog/memory/skill/graph/file/gap/request tabs. Raw response toggling replaces the rendered message body.
- Internal API action `browser.fetch` validates input before acquiring a bridge, then calls the production browser tool executor on the app-owned REST engine.

## Boundaries

The inspector records the myCoder outgoing payload. External native runtimes can add their own instructions and tool schemas, which this app cannot inspect through this local payload.

`context-preview` is a new-turn preview without chat history/ledger. `/api/messages` exposes the persisted context of an actual chat turn; that is the evidence for history-dependent assembly.

Static graph traversal is bounded and does not prove coverage of reflection, UI bindings, string-based configuration or external services. The model is explicitly told to search beyond the graph and explain update/remove/retain decisions.

The complete Chromium target was not rebuilt: the Ninja log became unreadable and the dry-run requested 56,476 actions. Existing component-app library linkage and the compiled `ShouldSaveWindowPlacement() == false` symbol were inspected; live behavior remains a separate check. See `BROWSER-VERIFICATION-2026-11-03.md` for details.
