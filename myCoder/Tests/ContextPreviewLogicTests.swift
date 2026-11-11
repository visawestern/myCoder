import Foundation
import Testing
@testable import myCoder

/// The built-in API is how every claim in this project is verified
/// (user directive 2026-11-03: «все проверяй через встроенное апи»).
/// `POST /api/context-preview` returns exactly what the model would receive,
/// split into the same tabs the viewer shows — so a live check needs no GUI.
@MainActor
@Suite("API предпросмотра контекста")
struct ContextPreviewLogicTests {

    private func compiledPreparation() throws -> SendContextPreparation {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let code = "func save() {}\nfunc reload() { save() }\n"
        try code.write(to: root.appendingPathComponent("Store.swift"), atomically: true, encoding: .utf8)
        let records = [FileIndexRecord(path: "Store.swift", hash: "h", size: code.utf8.count,
                                       lastModified: 0, language: "swift", searchableText: code)]
        return SendContextPreparationLogic.prepare(
            message: "reload save",
            records: records,
            projectPath: root.path,
            isEnabled: true,
            systemPrompt: "Ты агент. Инструменты: read_file."
        )
    }

    @Test("Пейлоад собранного пакета содержит стадии, вкладки и аудит-текст")
    func payloadForCompiledPack() throws {
        let preparation = try compiledPreparation()
        let payload = ContextPreviewLogic.payload(
            message: "reload save",
            preparation: preparation,
            stages: [.index, .memory, .skills, .graph, .impact, .files],
            systemPrompt: "Ты агент. Инструменты: read_file."
        )
        #expect(payload["status"] as? String == "compiled")
        let stages = try #require(payload["stages"] as? [String])
        #expect(stages.count == 6)
        #expect(stages.contains { $0.contains("граф") })
        let tabs = try #require(payload["tabs"] as? [[String: String]])
        #expect(tabs.first?["title"] == "Системная инструкция")
        let audit = try #require(payload["auditText"] as? String)
        #expect(audit.contains("Ты агент"))
        #expect(audit.contains("Store.swift:"))
        let included = try #require(payload["included"] as? [String])
        #expect(included == ["Store.swift"])
        #expect(payload["modelTextBytes"] as? Int ?? 0 > 0)
    }

    @Test("Пейлоад без проекта честно называет причину и не выдумывает вкладки")
    func payloadWithoutProject() {
        let preparation = SendContextPreparationLogic.prepare(
            message: "привет",
            records: [],
            projectPath: "",
            isEnabled: true,
            priorTurns: []
        )
        let payload = ContextPreviewLogic.payload(
            message: "привет",
            preparation: preparation,
            stages: [],
            systemPrompt: ""
        )
        #expect(payload["status"] as? String == "projectlessFirstTurn")
        #expect((payload["tabs"] as? [[String: String]])?.isEmpty == true)
        #expect((payload["summary"] as? String)?.isEmpty == false)
        #expect(payload["included"] as? [String] == [])
    }

    @Test("Выключенный контекст отличим от ошибки")
    func disabledIsItsOwnStatus() {
        let preparation = SendContextPreparationLogic.prepare(
            message: "привет",
            records: [],
            projectPath: "/tmp/x",
            isEnabled: false
        )
        let payload = ContextPreviewLogic.payload(
            message: "привет",
            preparation: preparation,
            stages: [],
            systemPrompt: ""
        )
        #expect(payload["status"] as? String == "disabled")
    }

    @Test("Ошибка сборки попадает в пейлоад, а не теряется")
    func warningIsCarried() {
        let preparation = SendContextPreparationLogic.prepare(
            message: "привет",
            records: [],
            projectPath: "/tmp/x",
            isEnabled: true,
            extraWarning: "⚠️ Память проекта не прочитана"
        )
        let payload = ContextPreviewLogic.payload(
            message: "привет",
            preparation: preparation,
            stages: [],
            systemPrompt: ""
        )
        #expect((payload["warning"] as? String)?.contains("Память проекта") == true)
    }
}
