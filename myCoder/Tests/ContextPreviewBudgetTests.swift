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
        let source = try RepoRoot.sourceText("myCoder/Sources/Views/ChatPanelView.swift")
        #expect(source.contains("ImpactBudget.runSync("))
        #expect(source.contains("ImpactAnalyzer.report("))
    }
}
