# Activity 58 — macOS Build Chain Audit

## Incident

The third native macOS log showed that the previous round had corrected individual lines but had not fully preserved each surrounding function chain. This activity manually traces each diagnostic from declaration to every affected caller and final consumer.

## Chain-by-chain trace

| Chain | Declaration/contract | Callers checked | Final issue and repair |
|---|---|---|---|
| CoreServices watcher | `FSEventStreamCreate` expects `FSEventStreamCreateFlags`/UInt32. The user SDK exposes `kFSEventStreamCreateFlagFileEvents` and `kFSEventStreamCreateFlagNoDefer` as `Int`. | `ProjectFileIndexWatcher.start()` and the existing watcher logic/tests. | The direct bitwise expression passed `Int`; it is now combined and explicitly converted through `UInt32(truncatingIfNeeded:)` into a typed `eventFlags` local before `FSEventStreamCreate`. |
| Model parameter display | `WebModelParameterProfile.values` contains optional numeric values consumed by `webProfilePanel`. | `ModelSettingsView.webProfilePanel`, model discovery profile storage, and the visible Text label. | `map(String.init)` was ambiguous on the native compiler. Each optional value now uses `map { String(describing: $0) }`, preserving the displayed fallback `—`. |
| Send button readiness | `SendReadinessLogic.canSendMessage` accepts the effective model as its `modelID` and has **no** `effectiveModelID` parameter. | Both `CenteredInputCard.canSend` and `CompactInputCard.canSend` were checked. | A broad prior edit had appended `effectiveModelID` to both can-send calls, producing “extra argument”. It is now removed from exactly those two calls. |
| Send blocker explanation | `SendReadinessReason.reason` has a separate `effectiveModelID` parameter declared at the end after `webConnected`. | Both visible `sendReason` computed properties in `InputViews` were checked independently from `canSend`. | `effectiveModelID` remains only in these two reason calls and is now the final argument. This preserves both compile contracts instead of applying one signature to both APIs. |

## Manual callsite audit

The full source tree was searched for `SendReadinessReason.reason`, `SendReadinessLogic.canSendMessage`, `selectModel`, `selectWebEffort`, and `FSEventStreamCreate`. The checked callers include AppState restore and `applySendSelections`, `MyCoderAPIServer`, ChatPanel, composer controls, provider settings, model settings, web-provider discovery, and the two InputViews send paths. No additional stale `effectiveModelID` was found in a `canSendMessage` call after the final repair.

## TDD evidence

`.acceptance/test_build_regressions_round104.py` was written before the production changes and failed on the missing typed FSEvents conversion. It was then kept strict enough to catch a second real mistake: appending `effectiveModelID` to `canSendMessage` while moving it in `SendReadinessReason`. The final green suite checks the two APIs separately, explicit numeric formatting, and the typed CoreServices bridge.

## Verification

| Gate | Result |
|---|---:|
| Round 104 red regression before fixes | **Failed as expected** |
| Round 104 source acceptance after chain repair | **PASS** |
| Round 102/103 compatibility acceptance | **PASS** |
| Full Foundation harness | **360/360 passed** |
| Registry integrity | **PASS** |
| Adversarial source checks | **12/12 passed** |
| Swift parser on affected files | **PASS** |
| `git diff --check` | **PASS** |

## Native boundary and scores

The Linux sandbox cannot run the user’s Xcode/macOS SwiftUI, CoreServices, or native SQLite type-check. The manual chain audit materially improves confidence because each changed function was traced through all known callers, but only a fresh native build can close the final verification boundary.

| Dimension | Score | Basis |
|---|---:|---|
| Implementation quality | 99/100 | Typed conversions and API-specific call signatures; no broad signature conflation remains. |
| Task adherence | 100/100 | The full chains were manually traced, including the regression caused by the previous broad edit. |
| Native build confidence | 92/100 | Exact third-log errors are addressed and all available gates pass; Xcode confirmation remains pending. |
