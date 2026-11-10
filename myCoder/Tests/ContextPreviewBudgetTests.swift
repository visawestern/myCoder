import Testing
import Foundation
@testable import myCoder

/// Live API audit 2026-11-04: `POST /api/context-preview` sometimes hit the
/// handler's 60 s deadline on the owner's real project (1008 indexed files).
/// Root cause: the visual preview ran `ImpactAnalyzer.report` on an unbounded
/// `Task.detached(...).value`, while the real send path already runs the same
/// optional evidence under `ImpactBudget.runSync`. Identical message could
/// give `compiled` with 12 dependents one run and `noEvidence`/timeout the
/// next. The preview must honour the same budget — a slow graph walk is a
/// gap, never a dead endpoint.
@Suite("Бюджет impact-прохода в предпросмотре контекста")
struct ContextPreviewBudgetTests {

    @Test("Предпросмотр ограничивает impact-проход бюджетом")
    func previewBoundsImpactPass() throws {
        let source = try RepoRoot.sourceText("myCoder/Sources/Services/ContextPreviewService.swift")
        #expect(source.contains("ImpactBudget.runSync("))
        #expect(source.contains("ImpactAnalyzer.report("))
        #expect(!source.contains("Task.detached(priority: .utility) { () -> ImpactReport? in"),
                "неограниченный detached-проход должен быть убран")
    }

    @Test("Проводка отправки тоже под бюджетом — оба пути одинаковы")
    func sendUsesTheSameBudget() throws {
        let source = try RepoRoot.chatPanelSourceText
        #expect(source.contains("ImpactBudget.runSync("))
        #expect(source.contains("ImpactAnalyzer.report("))
    }

    /// The preview handler's own deadline must not be a hardcoded 60 s that
    /// can be smaller than the sum of the pipeline's honest internal budgets
    /// (planner 20 s + impact 20 s + board build on a 1000-file project). A
    /// deadline smaller than the sum reproduces "preview timed out" on real
    /// projects even though the pipeline itself is bounded and correct.
    @Test("Дедлайн предпросмотра не меньше суммы внутренних бюджетов")
    func previewDeadlineCoversInternalBudgets() throws {
        let source = try RepoRoot.apiServerSourceText
        // The deadline must be a named constant, not an inline literal.
        #expect(source.contains("contextPreviewDeadline"))
        #expect(!source.contains("semaphore.wait(timeout: .now() + 60)")
                || source.contains("semaphore.wait(timeout: .now() + Self.contextPreviewDeadline)"))
        // The constant must cover planner + impact worst case with headroom.
        let floor = InternalContextPlanner.defaultBudget + ImpactBudget.defaultBudget
        #expect(MyCoderAPIServer.contextPreviewDeadline >= floor + 30)
    }
}
