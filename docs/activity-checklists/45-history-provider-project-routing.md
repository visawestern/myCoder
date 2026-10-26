# Activity 45 — Auto Free History, Zen Catalog, and Project Routing

## Audit objective

This round re-audits **CHAT-20**, the two provider stories formerly sharing **PROV-17**, and **DB-07 through DB-09**. The trace follows each action from the visible control or send route through validation, state mutation, persistence selection, reload, and user-visible result. The canonical registry was also tested as data: duplicate story IDs were treated as a documentation defect, not ignored.

## Full chain checklist

| Story | Chain audited | Expected behavior | Result |
|---|---|---|---|
| CHAT-20 | ChatPanel send → append current user and assistant placeholder → extract prior messages → filter history → Auto Free payload → stream response | Only completed, non-empty user/assistant turns are sent as prior context; current attachments stay on the new user turn; non-positive caps fail closed. | **Fixed Round 91; 4/4 Foundation tests pass; live request capture UNVERIFIED.** |
| PROV-17 | Add Provider → OpenCode Zen preset → base URL/type → `/models` response → anonymous/key catalog filtering → provider model section | One-click preset uses `https://opencode.ai/zen/v1`; anonymous mode exposes trusted free IDs; keyed mode adds only documented chat-compatible paid IDs; duplicate API rows produce one option. | **Fixed Round 91 duplicate catalog option; 4/4 Foundation tests pass; native/network verification UNVERIFIED.** |
| PROV-20 | Auto Free error → typed/textual rate-limit reason → switch state → NotificationCenter → red notification banner | 429/rate-limit switches are `NotificationType.error` and name from/to models; ordinary failure switches remain warning-level. | **Pass by source/tests; live provider and SwiftUI visual verification UNVERIFIED.** |
| DB-07 | New Project sheet fields/folder picker → validation → `createNewProject` → registry/project database | Blank, relative, missing, and file paths fail before persistence with actionable text; valid existing directories are normalized and created. | **Pass by source/tests; native folder picker and database runtime UNVERIFIED.** |
| DB-08 | Sidebar/overview/project selection → `AppState.selectWorkspace` → clear session UI → async project DB load → identity guard → visible session list | Switching projects cannot show the previous project’s sessions; late results for another project are discarded; selected project’s sessions appear after load. | **Pass by source/tests; SwiftUI async interaction UNVERIFIED.** |
| DB-09 | Explicit project ID → workspace path resolver → DatabaseBridge → project DB insert → session reload | Project B never inherits selected project A’s path; an unknown symbolic ID fails closed instead of silently writing to A. | **Fixed Round 91; 3/3 Foundation routing tests pass; native SQLite execution UNVERIFIED.** |

## Detailed manual trace

| # | Action/function | Chain and invariant | Result |
|---:|---|---|---|
| 1 | ChatPanel creates current messages | On a normal send, user content and an empty assistant placeholder are appended before route execution; retry updates the existing assistant turn. | **Pass by source.** |
| 2 | Prior-turn extraction | The Auto Free branch excludes the final current user/assistant pair, maps roles/content/finished state, then applies the pure history contract. | **Fixed/Pass.** |
| 3 | History filtering | System/unknown roles, blank content, unfinished assistant placeholders, and unfinished user turns are excluded. | **Fixed Round 91.** |
| 4 | History cap | The newest `maxTurns` completed turns remain; zero and negative values return no history instead of accidentally returning all rows. | **Fixed Round 91.** |
| 5 | Current attachments | Auto Free payload is appended to the new user message separately from prior text history. | **Pass by source/tests; live payload capture UNVERIFIED.** |
| 6 | OpenCode Zen preset | `addOpenCodeZenProvider` creates a stable `opencode-zen` custom provider with the hosted Zen URL, OpenAI endpoint type, no required key, and tools enabled. | **Pass by source/tests.** |
| 7 | Zen model discovery | AppState parses `data[].id` and `data[].name`, filters Zen models through `OpenCodeZenCatalog`, persists the catalog, and reconciles selection. | **Pass by source; live endpoint UNVERIFIED.** |
| 8 | Anonymous Zen mode | Blank/whitespace key exposes only trusted temporary free IDs. | **Pass by source/tests.** |
| 9 | Keyed Zen mode | Nonblank key adds only the curated chat-compatible paid list, never arbitrary paid or non-chat route IDs. | **Pass by source/tests.** |
| 10 | Duplicate live rows | Repeated free IDs are collapsed before sorting, preventing duplicate model choices and unstable selection rows. | **Fixed Round 91.** |
| 11 | Rate-limit classification | 429, `rate limit`, and `ratelimit` text normalize to the red reason; model-unavailable and generic failures retain distinct reasons. | **Pass by source/tests.** |
| 12 | Notification emission | Provider switch posts from/to/reason userInfo; AppState creates a transient and persisted error notification for rate limits. | **Pass by source/tests; visual banner UNVERIFIED.** |
| 13 | New Project validation | The sheet validates trimmed values before calling `createNewProject`; invalid results remain in the sheet and show `issue.message`. | **Pass by source/tests.** |
| 14 | Folder picker | NSOpenPanel allows directories, returns a selected path, clears the prior validation error, and fills an empty project name from the folder. | **Pass by source; AppKit interaction UNVERIFIED.** |
| 15 | Workspace switch | `selectWorkspace` changes identity, clears selected session and visible sessions, resets transient project UI, and starts an identity-tagged load. | **Pass by source/tests.** |
| 16 | Late session load | `shouldApplyLoadedSessions` requires a nonempty selected ID matching the loaded workspace; stale results are ignored. | **Pass by source/tests.** |
| 17 | Explicit session creation | AppState resolves project ID to a workspace path before `DatabaseBridge.createSession`; no selected-path fallback remains for unknown symbolic IDs. | **Fixed Round 91.** |
| 18 | Project DB insertion | DatabaseBridge resolves the real project directory and inserts into its per-project DB; invalid projects are rejected before insert. | **Pass by source; native SQLite runtime UNVERIFIED.** |
| 19 | Canonical registry | Every story ID is nonempty and unique; prior duplicate PROV-17, SID-20, and SID-21 rows are assigned distinct IDs. | **Fixed Round 91; persistent acceptance test green.** |

## Confirmed defects and TDD evidence

### CHAT-20 — unfinished user turns and negative caps leaked history

The existing logic excluded unfinished assistant placeholders but intentionally allowed unfinished user turns. Its comment promised only finished turns, so a still-streaming user row could enter a later anonymous request. A negative `maxTurns` also bypassed the cap because the old guard returned all cleaned rows for any value other than zero. Red tests were written first for both cases. The implementation now requires `turn.isFinished` and returns an empty history for all non-positive limits.

### PROV-17 — repeated free model rows created duplicate selections

`OpenCodeZenCatalog.availableModels` used `modelIDs.filter(isFreeModel)`, preserving duplicate rows from a provider response. The red test supplied repeated free IDs and required one sorted option per model. The fix deduplicates the trusted free IDs before combining and sorting with paid chat-compatible IDs.

### DB-09 — unknown symbolic project IDs inherited the selected path

`ProjectSessionRoutingLogic.path` returned `selectedPath ?? projectID` when a symbolic ID was absent from the workspace list. That could route an explicit project-B request into selected project A’s database. The red regression first required an unknown symbolic ID to return nil. The router now returns an optional path and AppState aborts before `DatabaseBridge.createSession` when resolution fails.

### Canonical registry — duplicate story IDs

A persistent Python acceptance regression was written before the documentation fix. It found 274 rows but only 271 unique IDs: PROV-17, SID-20, and SID-21 each appeared twice. The canonical rows now use PROV-20 for the rate-limit story, SID-27 for stable sidebar drag, and SID-28 for the responsive workspace toolbar. Historical reports retain their original round-era labels; the current registry is unique.

## Evidence

| Check | Result | Boundary |
|---|---:|---|
| CHAT-20 red unfinished-user and negative-cap tests | **failed as expected** | Both old contracts were violated |
| CHAT-20 green history suite | **4/4 passed** | Finished filtering, cap, zero, negative limit |
| PROV-17 red duplicate-catalog test | **failed as expected** | Repeated free rows were emitted twice |
| PROV-17 green Zen catalog suite | **4/4 passed** | Preset, anonymous, keyed, duplicate collapse |
| DB-09 red unknown-symbolic routing test | **failed as expected** | Old router inherited selected path |
| DB-09 green routing suite | **3/3 passed** | Explicit path, absolute fallback, fail-closed unknown ID |
| DB-07 validation suite | **4/4 passed** | Existing directory, missing, file, blank fields |
| DB-08 workspace selection suite | **3/3 passed** | Reload, stale result, nil selection |
| Canonical registry integrity | **274/274 unique IDs** | Persistent Python acceptance regression |
| Full Foundation harness | **303/303 passed** | Linux-safe suites |
| Adversarial source checks | **12/12 passed** | Existing web/model safety invariants |
| Swift parser validation | **passed** | All changed production/test Swift files |
| `git diff --check` | **passed** | No trailing whitespace |

## Status and scores

The confirmed source and documentation defects are fixed. Stories remain PARTIAL where the canonical contract depends on macOS AppKit/SwiftUI, SQLite, live OpenCode network responses, or authenticated runtime behavior. No Linux harness result is presented as native runtime proof.

| Story | Code quality | Task adherence | Target-runtime confidence |
|---|---:|---:|---:|
| CHAT-20 | 98/100 | 100/100 | 0/100 |
| PROV-17 | 98/100 | 100/100 | 0/100 |
| PROV-20 | 97/100 | 100/100 | 0/100 |
| DB-07 | 96/100 | 100/100 | 0/100 |
| DB-08 | 97/100 | 100/100 | 0/100 |
| DB-09 | 98/100 | 100/100 | 0/100 |
| Registry integrity | 98/100 | 100/100 | 100/100 |

> A provider response is untrusted input even when its schema is valid: a repeated model row must not become a repeated user choice. A project identifier is also untrusted input: when it cannot be resolved, inheriting the current workspace is more dangerous than refusing the write.
