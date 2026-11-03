import Foundation
import Testing
@testable import myCoder

@Suite("Turn delivery across transports")
struct TurnDeliveryTests {
    @Test func nativeRuntimeIsNotGivenAnUnconnectedEmulatedToolProtocol() {
        let native = TurnDelivery.systemInstruction(route: .mimoServe, userRules: "RULES", projectRoot: "/project", isProject: true, agentMode: .build)
        #expect(native.contains("RULES"))
        #expect(native.contains("native tools"))
        #expect(!native.contains("```tool"))
        let direct = TurnDelivery.systemInstruction(route: .openAICompatible(baseURL: "http://local", apiKey: nil, model: "model"), userRules: "RULES", projectRoot: "/project", isProject: true, agentMode: .build)
        #expect(direct.contains("```tool"))
        #expect(direct.contains("read_file"))
    }
    @Test func embeddedTransportReceivesSystemEveryTurn() {
        let wire = TurnDelivery.embedded(system: "SYSTEM", context: "EVIDENCE", request: "REQUEST")
        #expect(wire == "## Системная инструкция\nSYSTEM\n\n## Точечный контекст\nEVIDENCE\n\n## Запрос пользователя\nREQUEST")
        #expect(TurnDelivery.embedded(system: "SYSTEM", context: "", request: "SECOND").contains("SYSTEM"))
    }
    @Test func emptyIndexStillPreservesHistoryAndRules() {
        let result = SendContextPreparationLogic.prepare(message: "what next", records: [], projectPath: "/nonexistent", isEnabled: true, priorTurns: [.init(role: "user", content: "keep backwards compatibility", isFinished: true)], systemPrompt: "RULES")
        #expect(result.pack?.text.contains("keep backwards compatibility") == true)
        #expect(result.pack?.auditText.contains("RULES") == true)
    }
    @Test func noMatchingCodeRetainsPlannerGaps() {
        let result = SendContextPreparationLogic.prepare(message: "request", records: [], projectPath: "/nonexistent", isEnabled: true, localPlan: .init(plan: nil, status: .fallback(reason: "no internal model assigned"), dropped: []), systemPrompt: "RULES")
        #expect(result.pack?.text.contains("no internal model assigned") == true)
        #expect(result.pack?.unknowns.isEmpty == false)
    }
    @Test func codeFencesDoNotCreateFalseInspectionTabs() {
        let text = "## Файлы\n```md\n## this is source\n```\n\n## Запрос\nquestion"
        let tabs = TurnPresentation.sections(text)
        #expect(tabs.count == 2)
        #expect(tabs.first?.body.contains("## this is source") == true)
    }
}
