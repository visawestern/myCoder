import Foundation
import Testing
@testable import myCoder

@MainActor
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
    @Test func profileAndModeProduceOneHonestToolCatalog() {
        let minimal = ToolInstructionGuide.build(tools: HarnessProfile.minimal.tools, agentMode: .build)
        #expect(minimal.contains("### read_file"))
        #expect(!minimal.contains("### browser_fetch"))
        #expect(minimal.contains("available on request"))

        let plan = ToolInstructionGuide.build(tools: HarnessProfile.full.tools, agentMode: .plan)
        #expect(plan.contains("### task_create"))
        #expect(!plan.contains("### write_file"))
        #expect(plan.contains("Mode: Plan"))

        let compose = ToolInstructionGuide.build(tools: HarnessProfile.full.tools, agentMode: .compose)
        #expect(compose.contains("Mode: Compose"))
        #expect(!compose.contains("### task_create"))
        #expect(compose.contains("### run_command"))
        #expect(compose.contains("Read-only recognition is host policy"))
    }

    @Test func catalogRevisionTracksModeToolsSkillsAndMCP() {
        let first = ToolCatalogSnapshot(
            tools: HarnessProfile.minimal.tools,
            agentMode: .build,
            skillIDs: ["tdd-workflow"],
            mcpServerIDs: []
        )
        #expect(first.revision == ToolCatalogSnapshot(
            tools: HarnessProfile.minimal.tools.reversed(),
            agentMode: .build,
            skillIDs: ["tdd-workflow"],
            mcpServerIDs: []
        ).revision)
        #expect(first.revision != ToolCatalogSnapshot(
            tools: HarnessProfile.standard.tools,
            agentMode: .build,
            skillIDs: ["tdd-workflow"],
            mcpServerIDs: []
        ).revision)
        #expect(first.text.contains("tdd-workflow"))
        #expect(!first.text.contains("Installed MCP servers:"))
        #expect(first.text.contains("Catalog revision: \(first.revision)"))
    }

    @Test func systemInstructionRebuildsResourcesAndDoesNotPromiseUnavailableTools() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("mycoder-prompt-catalog-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let skillDir = MyCoderPaths.skillsDir(homeDirectory: home).appendingPathComponent("tdd-workflow")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        try "# Test skill".write(
            to: skillDir.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        let mcpURL = MyCoderPaths.mcpConfigURL(homeDirectory: home)
        try FileManager.default.createDirectory(at: mcpURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"mcpServers":{"docs":{"command":"docs-server"}}}"#.write(
            to: mcpURL, atomically: true, encoding: .utf8
        )
        let route = SendRoute.openAICompatible(baseURL: "http://local", apiKey: nil, model: "model")
        let minimal = TurnDelivery.systemInstruction(
            route: route, userRules: "", projectRoot: "/project", isProject: true,
            agentMode: .build, profile: .minimal, homeDirectory: home
        )
        #expect(minimal.contains("Catalog revision:"))
        #expect(minimal.contains("tdd-workflow"))
        #expect(minimal.contains("Installed MCP servers: docs"))
        #expect(!minimal.contains("### browser_fetch"))

        let plan = TurnDelivery.systemInstruction(
            route: route, userRules: "", projectRoot: "/project", isProject: true,
            agentMode: .plan, profile: .minimal, homeDirectory: home
        )
        #expect(plan.contains("You are in Plan mode"))
        #expect(!plan.contains("### write_file"))
        #expect(!plan.contains("write via write_file/edit_file"))
        #expect(plan != minimal)

        // Реальное изменение ресурсов читается заново, а не из кэша прошлого хода.
        try FileManager.default.removeItem(at: mcpURL)
        let withoutMCP = TurnDelivery.systemInstruction(
            route: route, userRules: "", projectRoot: "/project", isProject: true,
            agentMode: .build, profile: .minimal, homeDirectory: home
        )
        #expect(!withoutMCP.contains("Installed MCP servers: docs"))
        #expect(withoutMCP != minimal)
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
