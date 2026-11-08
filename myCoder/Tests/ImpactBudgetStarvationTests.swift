import Testing
import Foundation
@testable import myCoder

/// Full selftest 2026-11-04 (3418 tests in parallel) exposed a REAL hole, not
/// a flake: the deadline lived on `Task.sleep` inside Swift's cooperative
/// pool. When that pool is saturated with blocking work, the timer gets no
/// thread, so the "hanging" work wins the race (`"late"` after 5.0 s instead
/// of nil after 0.3 s) — the exact stall ImpactBudget exists to prevent.
/// This pins the failure deterministically without a whole-suite load.
@Suite("Дедлайн бюджета не зависит от cooperative pool")
struct ImpactBudgetStarvationTests {

    @Test("Перегруженный пул не откладывает дедлайн")
    func deadlineSurvivesStarvation() async throws {
        // Occupy cooperative threads with blocking work: longer than the
        // budget (100 ms), shorter than the work under test (600 ms) so the
        // deadline is unambiguously the winner that must be observed.
        for _ in 0..<16 {
            Task.detached(priority: .utility) {
                Thread.sleep(forTimeInterval: 0.8)
            }
        }
        // Let the blockers actually take their threads.
        try? await Task.sleep(for: .milliseconds(20))

        let outcome = await ImpactBudget.runSyncMeasuringDeadline(budget: .milliseconds(100)) {
            Thread.sleep(forTimeInterval: 0.6)
            return "late"
        }
        #expect(outcome.value == nil, "дедлайн обязан выиграть, даже когда cooperative pool занят")
        let delay = try #require(outcome.deadlineDelay, "дедлайн должен выиграть гонку")
        #expect(delay < 1.0, "дедлайн занял \(delay) с — таймер завис в пуле")
    }

    @Test("И при свободном пуле дедлайн срабатывает вовремя")
    func deadlineStillFiresWhenIdle() async throws {
        let outcome = await ImpactBudget.runMeasuringDeadline(budget: .milliseconds(100)) {
            try? await Task.sleep(for: .seconds(3))
            return "late"
        }
        #expect(outcome.value == nil)
        // Measured at the timer, inside the race: the deadline's own firing is
        // independent of when the cooperative pool schedules the caller's
        // continuation (which is load-sensitive in a fully parallel suite and
        // is a property of the scheduler, not of the budget).
        let delay = try #require(outcome.deadlineDelay, "дедлайн должен выиграть гонку")
        #expect(delay < 1.0, "дедлайн занял \(delay) с — таймер задержан")
    }
}
