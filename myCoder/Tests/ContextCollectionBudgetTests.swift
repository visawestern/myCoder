import Testing
import Foundation
@testable import myCoder

/// The user directive (2026-11-08): the CUMULATIVE context collection must
/// not exceed five minutes.
///
/// The stages had separate budgets — planner 20 s + impact 300 s — so the
/// collection could take 320 s (plus the unbounded board build, graph walk and
/// context compilation), and the preview endpoint waited 380 s. Each stage's
/// own limit is still needed, but no stage may push the collection past the
/// shared five-minute ceiling: every stage gets the lesser of its own limit
/// and what is left of the shared budget.
@Suite("Накопительный бюджет сбора контекста")
struct ContextCollectionBudgetTests {

    @Test("Общий лимит сбора контекста — пять минут")
    func totalIsFiveMinutes() {
        #expect(ContextCollectionBudget.total == 300,
                "накопительный сбор контекста ограничен \(ContextCollectionBudget.total) с — директива требует 300 с")
    }

    @Test("Остаток бюджета убывает и не уходит в минус")
    func remainingDecreases() {
        let started = Date()
        let fresh = ContextCollectionBudget.remaining(startedAt: started, now: started)
        #expect(abs(fresh - 300) < 0.001)
        let later = ContextCollectionBudget.remaining(startedAt: started, now: started.addingTimeInterval(120))
        #expect(abs(later - 180) < 0.001)
        let exhausted = ContextCollectionBudget.remaining(startedAt: started, now: started.addingTimeInterval(999))
        #expect(exhausted == 0)
    }

    @Test("Стадия получает минимум из своего лимита и остатка")
    func stageBudgetIsTheSmallerOfTheTwo() {
        let started = Date()
        // Plenty of budget left: the stage keeps its own (smaller) limit.
        let own = ContextCollectionBudget.stageBudget(ownLimit: 20, startedAt: started, now: started)
        #expect(abs(own - 20) < 0.001)
        // Budget nearly spent: the stage may not overrun the shared ceiling.
        let clamped = ContextCollectionBudget.stageBudget(
            ownLimit: 300,
            startedAt: started,
            now: started.addingTimeInterval(290)
        )
        #expect(abs(clamped - 10) < 0.001)
    }

    @Test("Исчерпанный бюджет отдаёт стадии ноль — стадия пропускается")
    func exhaustedBudgetGivesZero() {
        let started = Date()
        let budget = ContextCollectionBudget.stageBudget(
            ownLimit: 300,
            startedAt: started,
            now: started.addingTimeInterval(301)
        )
        #expect(budget == 0)
    }

    /// Both collection paths (real send and preview) must spend from the same
    /// shared budget instead of handing the impact pass the full 300 s after
    /// the planner has already used its own.
    @Test("Оба пути сбора тратят общий бюджет, а не каждый свой")
    func bothPathsSpendTheSharedBudget() throws {
        let sources: [(String, String)] = [
            ("ChatPanelView (все модули)", try RepoRoot.chatPanelSourceText),
            ("myCoder/Sources/Services/ContextPreviewService.swift",
             try RepoRoot.sourceText("myCoder/Sources/Services/ContextPreviewService.swift")),
        ]
        for (path, source) in sources {
            #expect(source.contains("ContextCollectionBudget.stageBudget("),
                    "\(path): стадии должны брать бюджет из общего остатка")
            #expect(!source.contains("budget: .seconds(ImpactBudget.defaultBudget)"),
                    "\(path): impact-проход не должен получать полные 300 с поверх уже потраченного времени")
        }
    }

    /// The preview endpoint waits for the whole pipeline plus the response.
    /// Its own HTTP deadline must cover the shared collection budget (plus the
    /// room to answer) and must not silently become a second, larger ceiling.
    @Test("Дедлайн предпросмотра покрывает общий бюджет сбора")
    func previewDeadlineCoversSharedBudget() throws {
        #expect(MyCoderAPIServer.contextPreviewDeadline >= ContextCollectionBudget.total,
                "дедлайн предпросмотра меньше общего бюджета сбора")
        #expect(MyCoderAPIServer.contextPreviewDeadline <= ContextCollectionBudget.total + 60,
                "дедлайн предпросмотра \(MyCoderAPIServer.contextPreviewDeadline) с — сбор контекста должен укладываться в 300 с")
    }
}
