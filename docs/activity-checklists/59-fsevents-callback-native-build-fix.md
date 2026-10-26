# Activity 59 — FSEvents Callback Native Build Fix

## Scope and incident

This activity audits the complete `ProjectFileIndexWatcher` callback chain after the user’s fourth macOS build log reported:

> `initializer for conditional binding must have Optional type, not 'UnsafeMutableRawPointer'`

The diagnostic appeared on `guard let info, let pathPointers` inside the `FSEventStreamCreate` callback. The reported line was not treated as an isolated typo. The callback declaration, context ownership, event-buffer conversion, invalidation logic, debounce scheduling, stop lifecycle, and Linux fallback were traced together.

## User story

> **As a myCoder user, I want project-file changes to invalidate the project index safely on macOS, so that background indexing remains responsive without preventing the application from building or risking an invalid callback pointer.**

## Expected behavior derived from source

When `start()` is called for a non-empty project path and no stream exists, the watcher creates an FSEvents stream with a retained-safe unretained context pointer, installs the serial utility callback queue, starts the stream, and leaves the watcher stopped if startup fails. When CoreServices invokes the callback, the optional client context is checked, the guaranteed event-path buffer is rebound to C-string pointers, all event paths are decoded, and `handle(paths:)` receives them. `handle(paths:)` ignores stopped watchers and irrelevant paths, coalesces relevant changes through the debounce interval, and invokes `onInvalidate(projectPath, generation)` only for the current watcher. `stop()` cancels pending work, stops and releases the stream, and is safe to call repeatedly. Outside CoreServices platforms the fallback remains constructible so shared Foundation contracts can be tested without claiming native runtime behavior.

## Full manual action and function checklist

| # | Action/function | Declaration → caller → consumer chain checked | Expected result | Quality | Task adherence | Evidence/status |
|---:|---|---|---|---:|---:|---|
| 1 | `ProjectFileIndexWatcher.init` | Stores standardized project path, generation, invalidation closure, callback queue, and empty stream state. | A watcher is ready but does not start work during initialization. | 100/100 | 100/100 | PASS by source trace |
| 2 | `start()` empty-path guard | `start()` → `guard stream == nil, !projectPath.isEmpty` → no CoreServices call. | Empty paths and duplicate starts are no-ops. | 100/100 | 100/100 | PASS by source trace |
| 3 | FSEvents context construction | `start()` → `FSEventStreamContext` → `Unmanaged.passUnretained(self).toOpaque()` → callback `info`. | Callback context identifies this watcher without an extra ownership cycle. | 100/100 | 100/100 | PASS by source trace; native ownership runtime UNVERIFIED |
| 4 | Native event flag construction | `start()` → constants → `UInt32(truncatingIfNeeded:)` → typed `FSEventStreamCreateFlags` → `FSEventStreamCreate`. | The macOS SDK’s integer constants satisfy the API’s typed flag parameter. | 100/100 | 100/100 | PASS by source acceptance; native compiler confirmation pending |
| 5 | `FSEventStreamCreate` callback signature | CoreServices callback → optional `info`, non-optional `pathPointers`, event count and metadata. | Only optional `info` is conditionally bound; the guaranteed raw path buffer is used directly. | 100/100 | 100/100 | PASS; Round 105 red regression |
| 6 | Missing callback context | callback → `guard let info else { return }`. | Malformed callback context cannot dereference an invalid watcher. | 100/100 | 100/100 | PASS by source trace |
| 7 | Event path buffer conversion | callback `pathPointers` → `assumingMemoryBound(to: UnsafePointer<CChar>.self)` → indexed C strings. | Every reported event path is decoded without incorrectly optional-binding a guaranteed pointer. | 100/100 | 100/100 | PASS by source acceptance; native runtime UNVERIFIED |
| 8 | Event path consumer | decoded `[String]` → `watcher.handle(paths:)`. | Callback does not mutate index state directly and routes through the watcher’s debounce/filter logic. | 100/100 | 100/100 | PASS by source trace |
| 9 | `handle(paths:)` stopped guard | `handle` → `!isStopped` → invalidation predicate. | Stopped watchers ignore late callback delivery. | 100/100 | 100/100 | PASS by Foundation harness |
| 10 | Relevant-path filter | `handle` → `ProjectFileIndexWatcherLogic.shouldInvalidate(changedPath:projectPath:)`. | Unrelated filesystem events do not invalidate the project. | 100/100 | 100/100 | PASS by Foundation harness |
| 11 | Debounce cancellation | `handle` → `pendingWork?.cancel()` → new `DispatchWorkItem`. | Bursts of file events coalesce instead of producing one invalidation per event. | 100/100 | 100/100 | PASS by Foundation harness |
| 12 | Invalidation callback | delayed work → weak watcher capture → `onInvalidate(projectPath,generation)`. | Invalidation carries the correct canonical path and generation and does not retain a dead watcher. | 100/100 | 100/100 | PASS by source trace; timing/native queue runtime UNVERIFIED |
| 13 | `stop()` stream lifecycle | `stop()` → queue sync → cancel work → stop/invalidate/release stream → nil. | Stream resources and pending work are released deterministically. | 100/100 | 100/100 | PASS by source trace; CoreServices runtime UNVERIFIED |
| 14 | Repeated `stop()` / deinit | `deinit` → `stop()` and optional stream branch. | Cleanup is idempotent and safe when no stream exists. | 100/100 | 100/100 | PASS by source trace |
| 15 | FSEvent startup failure | `FSEventStreamStart == false` → invalidate/release → stream nil. | A failed native start does not leave a partially active stream. | 100/100 | 100/100 | PASS by source trace; native runtime UNVERIFIED |
| 16 | Linux fallback | `#else` fallback type → same initializer shape → AppState lifecycle. | Foundation-only builds retain one lifecycle path without pretending FSEvents exists. | 100/100 | 100/100 | PASS by Foundation harness |
| 17 | Regression acceptance | old invalid guard → red assertion; corrected guard → green assertion. | The exact compiler regression cannot silently return in a later edit. | 100/100 | 100/100 | PASS: `test_build_regressions_round105.py` |

## TDD record

The red regression was written before production modification in `.acceptance/test_build_regressions_round105.py`. It failed against the old source because `guard let info else { return }` was absent. The implementation then removed only the invalid optional binding for `pathPointers`, preserving the callback’s existing context validation, pointer conversion, path decoding, and downstream `handle(paths:)` chain. The acceptance turned green after the minimal fix.

## Verification gates

| Gate | Result |
|---|---:|
| Round 105 red regression before fix | **Failed as expected** |
| Round 105 source acceptance after fix | **PASS** |
| Round 102 compatibility acceptance | **PASS** |
| Round 103 compatibility acceptance | **PASS** |
| Round 104 compatibility acceptance | **PASS** |
| Foundation harness | **360/360 passed** |
| Feature registry integrity | **274 unique rows; 224 PASS, 45 PARTIAL, 0 MISSING, 5 FUTURE** |
| Adversarial source checks | **12/12 passed** |
| Swift parser on affected file | **PASS** |
| `git diff --check` | **PASS** |
| Native macOS `./build-app.sh` | **PENDING user rerun** |

## Boundary and separate quality ratings

The implementation quality is **100/100** for the confirmed defect: the fix is minimal, API-signature-specific, covered by a persistent regression, and does not mix unrelated callback or lifecycle edits. Task adherence is **100/100** for this round: the complete declaration-to-consumer chain and each watcher action were traced before documentation and publication. Native runtime confidence is **92/100** until the user runs the fresh macOS build and, ideally, observes a real project-file invalidation; Linux cannot compile or execute CoreServices, SwiftUI, AppKit, or Xcode behavior.
