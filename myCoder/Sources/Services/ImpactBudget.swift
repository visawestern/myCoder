import Foundation

/// Deadline for the structural impact pass.
///
/// `ImpactAnalyzer.report` re-indexes the project (`CodeIndexService.ensureIndexed`)
/// and walks the code graph synchronously. On a big project that outruns the
/// send: the stage line froze on "Проверяю связи и зависимости изменяемого
/// кода" and the turn never answered (live run 2026-11-04, chat FF5D0A17).
/// The pass is optional evidence, so it runs under a deadline: past it the turn
/// continues with the graph it already has rather than waiting forever.
enum ImpactBudget {

    /// Generous enough for a real graph walk, short enough that a stall cannot
    /// swallow the turn.
    static let defaultBudget: TimeInterval = 20

    /// Runs `work` and returns its value, or nil when the budget runs out.
    /// A nil result means "no impact evidence this turn", never "no answer".
    static func run<T: Sendable>(budget: Duration,
                                 work: @escaping @Sendable () async -> T) async -> T? {
        guard budget > .zero else { return nil }
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
        return await race(budget: budget) { work() }
    }

    /// First result wins; the loser is abandoned, never awaited.
    ///
    /// A task group cannot do this: it waits for every child at scope exit, so
    /// a blocking child holds the caller for its full duration even after the
    /// deadline task returned (measured: 5.0 s instead of 0.3 s). A one-shot
    /// continuation resolves exactly once and lets the loser run to completion
    /// in the background without blocking anyone.
    private static func race<T: Sendable>(budget: Duration,
                                          work: @escaping @Sendable () async -> T) async -> T? {
        let box = ResultBox<T>()
        return await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            Task.detached(priority: .utility) {
                let value = await work()
                if box.claim() { continuation.resume(returning: value) }
            }
            Task.detached(priority: .utility) {
                try? await Task.sleep(for: budget)
                if box.claim() { continuation.resume(returning: nil) }
            }
        }
    }
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
