import Testing
import Foundation
@testable import myCoder

/// Требование владельца 2026-11-09: вызов, прописанный моделью, но не
/// исполненный, всё равно должен быть виден под спойлером — с конкретной
/// причиной, как ошибка валидации.
@Suite("Неисполненные вызовы инструментов")
struct ToolCallSkipReasonTests {

    @Test("Причины сформулированы конкретно")
    func reasonTexts() {
        #expect(ToolCallSkipReason.iterationLimit(15).text.contains("iteration limit (15)"))
        #expect(ToolCallSkipReason.cancelled.text.contains("stopped"))
        #expect(ToolCallSkipReason.malformedBlock("unclosed brace").text.contains("unclosed brace"))
        #expect(ToolCallSkipReason.awaitingApproval.text.contains("approval"))
    }

    @Test("Часть вызова несёт имя, аргументы, причину и callID")
    func partCarriesReason() {
        let part = UnexecutedToolCallLogic.part(
            name: "read_file",
            arguments: ["path": "a.swift", "offset": "10"],
            callID: "c1",
            reason: .iterationLimit(5)
        )
        guard case .toolCall(let name, let args, let result, let id) = part else {
            Issue.record("expected toolCall part")
            return
        }
        #expect(name == "read_file")
        #expect(args == "offset=10 path=a.swift")
        #expect(result?.contains("iteration limit (5)") == true)
        #expect(id == "c1")
    }

    @Test("parts(for:) создаёт по спойлеру на каждый вызов")
    func partsForCalls() {
        let calls = [
            WebToolCall(name: "read_file", arguments: ["path": "a"]),
            WebToolCall(name: "grep", arguments: ["pattern": "b"])
        ]
        let parts = UnexecutedToolCallLogic.parts(for: calls, reason: .cancelled)
        #expect(parts.count == 2)
        let names = parts.compactMap { part -> String? in
            if case .toolCall(let name, _, _, _) = part { return name }
            return nil
        }
        #expect(names == ["read_file", "grep"])
        let reasons = parts.compactMap { part -> String? in
            if case .toolCall(_, _, let result, _) = part { return result }
            return nil
        }
        #expect(reasons.allSatisfy { $0.contains("stopped") })
    }

    @Test("Битый ```tool блок отдаёт причину для спойлера")
    func malformedBlockInfo() {
        // Не JSON вовсе: ремонт JSON тут не спасает, имя не восстановить.
        let text = "```tool\nread_file path=a\n```"
        let malformed = WebToolProtocolEmulator.malformedToolCall(from: text)
        #expect(malformed?.name == "tool")
        #expect(malformed?.problem.isEmpty == false)
    }

    @Test("Обрезанный DSML-блок не теряется: имя + причина")
    func malformedDSMLBlockInfo() {
        let text = """
        <｜DSML｜ invoke name="read_file">
        <｜DSML｜ parameter name="path">myCoder/Package.swift
        """
        let malformed = WebToolProtocolEmulator.malformedToolCall(from: text)
        #expect(malformed?.name == "read_file")
        #expect(malformed?.problem.contains("DSML") == true)
    }

    @Test("Полноценный DSML-блок не считается битым")
    func validDSMLIsNotMalformed() {
        let text = """
        <｜DSML｜ invoke name="read_file">
        <｜DSML｜ parameter name="path">a.swift</｜DSML｜ parameter>
        </｜DSML｜ invoke>
        """
        #expect(WebToolProtocolEmulator.malformedToolCall(from: text) == nil)
    }
}
