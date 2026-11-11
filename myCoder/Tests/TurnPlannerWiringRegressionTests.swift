import Testing
@testable import myCoder

@MainActor
@Suite("Turn model and retrieval integration")
struct TurnPlannerWiringRegressionTests {
    @Test func plannerContextUsesActualTaskSources() throws {
        let source = try RepoRoot.chatPanelSourceText
        let planner = try RepoRoot.sourceText("myCoder/Sources/Services/TurnContextPlanningService.swift")
        #expect(planner.contains("taskContext:"))
        #expect(planner.contains("graphContext:"))
        #expect(planner.contains("skillIDs:"))
        #expect(source.contains("semanticTerms:"))
        #expect(source.contains("preparedSystemPrompt: sysPrompt"))
        #expect(source.contains("TurnDelivery.withSystem(sysPrompt"))
    }
    @Test func modelQuestionsReachTheMainModelPack() {
        let plan = LocalQueryPlan(intent: .refactor, terms: [], symbols: [], files: [], memoryTags: [], questions: ["Is the folder picker still needed?"], skills: [])
        let pack = TurnContextCompiler.compile(message: "Move frames to memory", board: .init(projectPath: "", entries: [], builtAt: .distantPast), projectRoot: "", localPlan: .init(plan: plan, status: .local(model: "internal-test"), dropped: []))
        #expect(pack.text.contains("Is the folder picker still needed?"))
        #expect(TurnPresentation.sections(pack.auditText).last?.title == "Запрос")
    }
}
