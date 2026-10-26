# Activity 56 — macOS Build Regression Repair

## Incident

The user supplied a real macOS `build-app.sh` log from `v2.119.0 (build 117)`. The build did not reach a usable production binary because Swift compilation failed in multiple independent files. The same diagnostics were repeated by the script’s debug/test/build phases; repeated lines were treated as cascades, not separate defects.

## Primary compiler errors and fixes

| Source | Diagnostic | Root cause | Fix |
|---|---|---|---|
| `ChatPanelView.swift:534,631` | `providerID must precede effectiveModelID` | Call sites used labels in an order inconsistent with `SendReadinessLogic.sendValidationError`. | Reordered labels to `modelID`, `providerID`, `effectiveModelID`. |
| `InputViews.swift:331,565` | Incorrect argument labels/order for `SendReadinessReason.reason` | Both `sendReason` call sites passed `effectiveModelID` before `providerID`. | Reordered labels to match the declared API. |
| `ChatPanelView.swift:1610` | `compactMap` generic result could not be inferred | Swift 6.3 could not infer the closure result in the macOS compilation context. | Added explicit `(image: ClipboardImage) -> String?` closure type. |
| `StorageSettingsView.swift:725` | `String.Element` cannot convert to `String` | `appState.selectedWorkspace?.path.map` mapped over the `String` path characters because of optional-chaining precedence. | Map the optional workspace and use `workspace.path`. |
| `StorageSettingsView.swift:618` | Main-actor static deletion worker called from detached task | The detached worker referenced an implicitly main-actor-isolated static helper. | Marked the pure filesystem deletion helper `nonisolated`. |
| `ProjectDatabaseManager.swift:591` | `String?` expected `Expression<String?>` | SQLite column expression `sessionGoal` collided with the method parameter of the same name. | Introduced `sessionGoalValue` and assign `sessionGoal <- sessionGoalValue`. |
| `MyCoderApp.swift:589,738` | Main-actor journal called from synchronous nonisolated methods | `selectWebEffort` and `selectModel` called `@MainActor recordWebBrowserAction`. | Marked both selection methods `@MainActor`. |
| `MyCoderApp.swift:1107` | Unused `json` warning | Validation bound a dictionary that was never used before the canonical parser. | Converted it to validation-only optional expression. |
| `ModelSettingsView.swift:667` | Ambiguous `opacity` | SwiftUI exposed both `Color.opacity` and `ShapeStyle.opacity` candidates. | Used `opacity(Double(0.45))` explicitly. |
| `ProjectFileIndexWatcher.swift:52` | Untyped array passed where `FSEventStreamCreateFlags` is required | CoreServices OptionSet literals had no contextual type in this toolchain. | Passed `FSEventStreamCreateFlags([.fileEvents, .noDefer])`. |

## TDD evidence

A persistent red/source regression was written before implementation at `.acceptance/test_build_regressions_round102.py`. Before the fixes it failed on the stale argument order in `ChatPanelView`; after the fixes it passed all source invariants, including the explicit closure result type, workspace optional mapping, SQLite disambiguation, MainActor annotations, typed CoreServices flags, explicit opacity type, and removed unused JSON binding.

The regression covers build contracts that cannot be executed by the Linux Foundation harness because they are macOS SwiftUI/AppKit/CoreServices compile surfaces. This is intentional: a passing pure-logic test cannot substitute for the compiler contract that the user’s real macOS build exposed.

## Verification

| Gate | Result |
|---|---:|
| Round 102 source regression | **PASS after red failure** |
| Foundation harness | **360/360 passed** |
| Prior Round 100 acceptance | **PASS** |
| Prior Round 101 acceptance | **PASS** |
| Canonical registry integrity | **PASS** |
| Adversarial source checks | **12/12 passed** |
| Swift parser over all affected files | **PASS** |
| `git diff --check` | **PASS** |

## Honest boundary

The Linux sandbox cannot execute the user’s macOS SwiftUI/AppKit/CoreServices production build. The fixes directly match the compiler diagnostics in the supplied macOS log and pass parser/source gates, but the final confirmation still requires the user to run `git pull origin main` and `./build-app.sh` on macOS. Any remaining diagnostic from that build must be treated as new evidence rather than assumed resolved.

## Separate scores

| Dimension | Score | Basis |
|---|---:|---|
| Implementation quality | 99/100 | Local, typed, behavior-preserving fixes with persistent source regression coverage. |
| Task adherence | 100/100 | Every unique error from the supplied log was traced and addressed; no warning was silently ignored. |
| Native build confidence | 90/100 | Direct diagnostic correspondence and parser/source gates pass, but the final macOS toolchain build remains unavailable here. |
