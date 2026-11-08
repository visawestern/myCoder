import Foundation

/// Shared ceiling for the CUMULATIVE context collection (user directive,
/// 2026-11-08): every stage of the collection — planner, board build, impact
/// pass, context compilation — together must not take more than five minutes.
///
/// Each stage keeps its own (smaller) limit, but no stage may spend more than
/// what is left of the shared budget: the collection as a whole stops at
/// `total`, no matter how the stages are ordered or how slow one of them is.
enum ContextCollectionBudget {

    /// The shared ceiling: five minutes for the whole collection.
    static let total: TimeInterval = 300

    /// Seconds left of the shared budget since the collection started.
    /// Never negative: an exhausted budget means "stop collecting".
    static func remaining(startedAt: Date, now: Date = Date()) -> TimeInterval {
        max(0, total - now.timeIntervalSince(startedAt))
    }

    /// The budget a stage may spend: the lesser of its own limit and what is
    /// left of the shared budget. Zero means the stage must be skipped — the
    /// collection is over, whatever the stage's own limit says.
    static func stageBudget(ownLimit: TimeInterval, startedAt: Date, now: Date = Date()) -> TimeInterval {
        min(ownLimit, remaining(startedAt: startedAt, now: now))
    }
}
