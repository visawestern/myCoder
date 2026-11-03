import Foundation
import Testing
@testable import myCoder

struct TaskInstructionDeliveryTests {
    @Test func modelSelectedWorkflowIsActuallySentToMainModel() {
        let plan = LocalQueryPlan(intent: .refactor, terms: [], symbols: [], files: [], memoryTags: [], instructions: ["Verify whether the folder picker is still used by export."])
        let pack = TurnContextCompiler.compile(message: "Move frames into memory", board: .init(projectPath: "", entries: [], builtAt: .distantPast), projectRoot: "", localPlan: .init(plan: plan, status: .local(model: "internal"), dropped: []))
        #expect(pack.text.contains("Verify whether the folder picker is still used by export."))
        #expect(pack.sections.contains { $0.title == "Инструкции задачи" })
        #expect(TurnPresentation.inspectionTabs(pack.auditText).contains { $0.title == "Задача" })
    }
    @Test func directSystemCarriesPurposeAndParameterContractOfEveryHostTool() {
        let system = TurnDelivery.systemInstruction(route: .openAICompatible(baseURL: "http://local", apiKey: nil, model: "model"), userRules: "", projectRoot: "/project", isProject: true, agentMode: .build)
        for tool in WebEmulatedTool.allCases {
            #expect(system.contains(tool.description), "Missing purpose: \(tool.rawValue)")
            #expect(system.contains(tool.argumentSchema), "Missing parameters: \(tool.rawValue)")
        }
    }
}
