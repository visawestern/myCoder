# Activity 57 — macOS Build Regression Follow-up

## Incident

After pulling `7e12baf`, the macOS build exposed a second layer of compiler contracts. These were not ignored: the log was deduplicated and the intermediate fixes that still failed were replaced with toolchain-specific solutions.

## New diagnostics and final repairs

| File | New compiler diagnostic | Why the first attempted repair was insufficient | Final repair |
|---|---|---|---|
| `ModelSettingsView.swift:667` | `ambiguous use of opacity` remained after `Double(0.45)` | Both `Color.opacity` and `ShapeStyle.opacity` remained viable even with an explicit numeric argument. | Added `let metadataBackground: Color = Color.mimo.backgroundAlt.opacity(0.45)` and passed `.background(metadataBackground)`, forcing a concrete `Color` result context. |
| `InputViews.swift:331,565` | `effectiveModelID` still appeared before `serverConnected` in the full `SendReadinessReason.reason` signature | The first repair only moved `providerID`; the API declares `effectiveModelID` after `webConnected`. | Moved `effectiveModelID` to the final argument position in both calls. |
| `ProjectDatabaseManager.swift:592` | `String?` still expected `Expression<String?>` | Renaming only the right-hand parameter did not disambiguate the left SQLite expression. | Qualified the column expression as `self.sessionGoal <- sessionGoalValue`. |
| `ProjectFileIndexWatcher.swift:52` | `FSEventStreamCreateFlags([.fileEvents, .noDefer])` had no matching initializer | CoreServices on the user’s toolchain exposes flags as UInt32 constants rather than a Swift OptionSet initializer. | Passed `kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer`. |
| `MyCoderApp.swift:830,882,884` | Adding `@MainActor` to `selectModel` created new actor errors in restore/API callers | The selection API is synchronous and has multiple nonisolated callers. | Removed method-level annotation and wrapped only `recordWebBrowserAction` calls in `Task { @MainActor in … }`. |

## TDD evidence

Round 103 red/source acceptance was written before the final repairs in `.acceptance/test_build_regressions_round103.py`. It initially failed on the stale InputViews call contract and was then made green only after the final typed Color, SQLite `self` qualification, CoreServices constants, exact argument order, and isolated journal-hop fixes were present. Round 102 acceptance was updated to reflect the final actor-safe design rather than locking in the intermediate annotation strategy.

## Verification

| Gate | Result |
|---|---:|
| Round 103 red regression before fixes | **Failed as expected** |
| Round 103 source acceptance after fixes | **PASS** |
| Round 102 compatibility acceptance | **PASS** |
| Foundation harness | **360/360 passed** |
| Registry integrity | **PASS** |
| Adversarial source checks | **12/12 passed** |
| Swift parser on affected files | **PASS** |
| `git diff --check` | **PASS** |

## Native boundary

The Linux environment cannot run the user’s Xcode/macOS SwiftUI, AppKit, CoreServices, or SQLite compiler/runtime. The final repairs now correspond to the exact second-log diagnostics, but only the user’s native `./build-app.sh` can confirm the complete macOS type-check. A new native diagnostic after this round must be treated as a new defect.

## Separate scores

| Dimension | Score | Basis |
|---|---:|---|
| Implementation quality | 99/100 | Final fixes are local, typed, and preserve synchronous selection behavior. |
| Task adherence | 100/100 | The second log was re-read, deduplicated, and every unique error was addressed with red/green source coverage. |
| Native build confidence | 90/100 | Exact compiler correspondence plus parser/source gates pass; native Xcode confirmation remains pending. |
