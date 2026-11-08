import Foundation
import Dispatch

/// Deadline for the structural impact pass.
///
/// `ImpactAnalyzer.report` re-indexes the project (`CodeIndexService.ensureIndexed`)
/// and walks the code graph synchronously. On a big project that outruns the
/// send: the stage line froze on "Проверяю связи и зависимости изменяемого
/// кода" and the turn never answered (live run 2026-11-04, chat FF5D0A17).
/// The pass is optional evidence, so it runs under a deadline: past it the turn
/// continues with the graph it already has rather than waiting forever.
enum ImpactBudget {

    /// Five minutes for a real graph walk on a large project. The user
    /// directive (2026-11-08) raised this from 20 s to 300 s so the impact
    /// pass can finish on big codebases; the turn still continues (with the
    /// graph it already has) if a stall outruns even this.
    static let defaultBudget: TimeInterval = 300

    /// Runs `work` and returns its value, or nil when the budget runs out.
    /// A nil result means "no impact evidence this turn", never "no answer".
    static func run<T: Sendable>(budget: Duration,
                                 work: @escaping @Sendable () async -> T) async -> T? {
        guard budget > .zero else { return nil }
        return await race(budget: budget) { await work() }.value
    }

    /// Same race as `run`, but it also reports WHEN the deadline timer fired.
    ///
    /// The delay is measured inside the race, at the timer — not by the
    /// caller. A fully parallel suite saturates the cooperative pool, so the
    /// caller's continuation can be scheduled seconds late; that delay
    /// measures the scheduler, not the budget. The deadline delay is the
    /// property the budget actually owns.
    static func runMeasuringDeadline<T: Sendable>(budget: Duration,
                                                  work: @escaping @Sendable () async -> T) async -> DeadlineOutcome<T> {
        guard budget > .zero else { return DeadlineOutcome(value: nil, deadlineDelay: 0) }
        return await race(budget: budget) { await work() }
    }

    /// Runs the synchronous analyzer OFF the caller's actor under the deadline.
    ///
    /// The detached hop is the whole point. `ImpactAnalyzer.report` blocks
    /// (SQLite + file parsing); run inline from a `@MainActor` view it froze the
    /// main actor, so `/api/state` stopped answering and the send died silently
    /// (live run 2026-11-04). A detached task cannot inherit the caller's actor,
    /// so the deadline can actually fire.
    static func runSync<T: Sendable>(budget: Duration = .seconds(defaultBudget),
                                     work: @escaping @Sendable () -> T) async -> T? {
        guard budget > .zero else { return nil }
        return await race(budget: budget) { work() }.value
    }

    /// Same race as `runSync`, but it also reports WHEN the deadline timer
    /// fired — measured at the timer, see `runMeasuringDeadline`.
    static func runSyncMeasuringDeadline<T: Sendable>(budget: Duration = .seconds(defaultBudget),
                                                      work: @escaping @Sendable () -> T) async -> DeadlineOutcome<T> {
        guard budget > .zero else { return DeadlineOutcome(value: nil, deadlineDelay: 0) }
        return await race(budget: budget) { work() }
    }

    /// First result wins; the loser is abandoned, never awaited.
    ///
    /// A task group cannot do this: it waits for every child at scope exit, so
    /// a blocking child holds the caller for its full duration even after the
    /// deadline task returned (measured: 5.0 s instead of 0.3 s). A one-shot
    /// continuation resolves exactly once and lets the loser run to completion
    /// in the background without blocking anyone.
    ///
    /// The deadline runs on a DEDICATED thread (`DeadlineTimer`), not on a
    /// queue: both GCD's global queue and Swift's cooperative pool are
    /// exhausted under load (full selftest 2026-11-04: thousands of parallel
    /// tests, many of them blocking), and a timer scheduled there fired
    /// seconds late — measured 4.2 s for a 100 ms deadline, which defeats the
    /// whole point of a budget. The cooperative `Task.sleep` stays as a
    /// second line of defence; `ResultBox` guarantees only one resume, so the
    /// losing timer is a harmless no-op.
    private static func race<T: Sendable>(budget: Duration,
                                          work: @escaping @Sendable () async -> T) async -> DeadlineOutcome<T> {
        let box = ResultBox<T>()
        let started = DispatchTime.now()
        return await withCheckedContinuation { (continuation: CheckedContinuation<DeadlineOutcome<T>, Never>) in
            let components = budget.components
            let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
            DeadlineTimer.shared.schedule(after: seconds) {
                if box.claim() {
                    let delay = elapsedSince(started)
                    continuation.resume(returning: DeadlineOutcome(value: nil, deadlineDelay: delay))
                }
            }
            Task.detached(priority: .utility) {
                let value = await work()
                if box.claim() {
                    continuation.resume(returning: DeadlineOutcome(value: value, deadlineDelay: nil))
                }
            }
            Task.detached(priority: .utility) {
                try? await Task.sleep(for: budget)
                if box.claim() {
                    let delay = elapsedSince(started)
                    continuation.resume(returning: DeadlineOutcome(value: nil, deadlineDelay: delay))
                }
            }
        }
    }

    /// Seconds since the race started — monotonic, immune to clock changes.
    private static func elapsedSince(_ started: DispatchTime) -> TimeInterval {
        let now = DispatchTime.now().uptimeNanoseconds
        let then = started.uptimeNanoseconds
        guard now > then else { return 0 }
        return Double(now - then) / 1_000_000_000
    }
}

/// Outcome of a budgeted run.
///
/// `value` is nil when the deadline won the race. `deadlineDelay` is how long
/// the deadline timer took to fire, measured inside the race — nil when the
/// work finished before the deadline.
struct DeadlineOutcome<T: Sendable>: Sendable {
    let value: T?
    let deadlineDelay: TimeInterval?
}

/// One-shot latch: exactly one racer may resume the continuation.
private final class ResultBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}
