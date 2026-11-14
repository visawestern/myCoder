import Foundation
import Testing
@testable import myCoder

/// БД-слой ленивой загрузки результатов тулов: lite-чтение частей без
/// текстов результатов и пакетный запрос результатов по callID.
@Suite("БД: ленивые результаты тулов (lite + batch)")
struct DatabaseManagerToolResultsTests {

    private func makeDB() throws -> DatabaseManager {
        let db = DatabaseManager(inMemory: true)
        try db.insertMessage(id: "m1", sessionId: "s1", role: "assistant", content: "ответ")
        try db.insertMessagePart(
            id: "p-tool-1", messageId: "m1", type: "tool_call",
            content: nil, toolName: "read", toolArgs: #"{"path":"a"}"#,
            toolResult: "{\"ok\":true,\"data\":\"длинный результат\"}",
            toolCallId: "c1", sequenceOrder: 0
        )
        try db.insertMessagePart(
            id: "p-tool-2", messageId: "m1", type: "tool_call",
            content: nil, toolName: "write", toolArgs: #"{"path":"b"}"#,
            toolResult: nil, toolCallId: "c2", sequenceOrder: 1
        )
        try db.insertMessagePart(
            id: "p-text", messageId: "m1", type: "text",
            content: "просто текст", toolName: nil, toolArgs: nil,
            toolResult: nil, toolCallId: nil, sequenceOrder: 2
        )
        return db
    }

    @Test("Lite-чтение не отдаёт текст результата, но сообщает о его наличии и длине")
    func liteReadOmitsResultText() throws {
        let db = try makeDB()
        let lite = try db.getMessagePartsLite(messageId: "m1")
        #expect(lite.count == 3)

        let tool1 = lite[0]
        #expect(tool1.type == "tool_call")
        #expect(tool1.toolCallId == "c1")
        #expect(tool1.hasToolResult)
        #expect(tool1.toolResultLength == "{\"ok\":true,\"data\":\"длинный результат\"}".count)
        #expect(!tool1.type.contains("tool_result"))

        let tool2 = lite[1]
        #expect(!tool2.hasToolResult)
        #expect(tool2.toolResultLength == 0)

        let text = lite[2]
        #expect(text.type == "text")
        #expect(!text.hasToolResult)
    }

    @Test("Пакетный запрос возвращает только реально существующие результаты")
    func batchFetchReturnsExistingOnly() throws {
        let db = try makeDB()
        let results = try db.getToolResults(callIDs: ["c1", "missing", "c2"])
        #expect(results.keys.count == 1)
        #expect(results["c1"] == "{\"ok\":true,\"data\":\"длинный результат\"}")
    }

    @Test("Пустой список callID даёт пустой словарь")
    func emptyBatchFetch() throws {
        let db = try makeDB()
        #expect(try db.getToolResults(callIDs: []) == [:])
    }

    @Test("Результат с пустой строкой считается существующим и возвращается")
    func emptyResultPreserved() throws {
        let db = DatabaseManager(inMemory: true)
        try db.insertMessage(id: "m2", sessionId: "s1", role: "assistant", content: "x")
        try db.insertMessagePart(
            id: "p1", messageId: "m2", type: "tool_call",
            content: nil, toolName: "read", toolArgs: "{}",
            toolResult: "", toolCallId: "c-empty", sequenceOrder: 0
        )
        let lite = try db.getMessagePartsLite(messageId: "m2")
        #expect(lite[0].hasToolResult)
        #expect(lite[0].toolResultLength == 0)
        #expect(try db.getToolResults(callIDs: ["c-empty"]) == ["c-empty": ""])
    }

    @Test("Полный цикл: lite → meta → batch-запрос → apply возвращает результат")
    func fullLiteCycle() throws {
        let db = try makeDB()

        // 1. Lite-чтение даёт метаданные, но не текст.
        let lite = try db.getMessagePartsLite(messageId: "m1")
        let tool = lite.first { $0.type == "tool_call" && $0.toolCallId == "c1" }
        #expect(tool?.hasToolResult == true)
        #expect(tool?.toolResultLength == "{\"ok\":true,\"data\":\"длинный результат\"}".count)

        // 2. Meta попадает в Message.
        let meta: [String: ToolResultMeta] = [
            tool!.toolCallId!: ToolResultMeta(
                callID: tool!.toolCallId!,
                hasStoredResult: tool!.hasToolResult,
                length: tool!.toolResultLength
            )
        ]
        let parts: [MessagePartContent] = [
            .toolCall(name: "read", args: #"{"path":"a"}"#, result: nil, callID: "c1"),
        ]
        let message = Message(id: "m1", role: .assistant, content: "ответ", parts: parts, toolResultMeta: meta)

        // 3. Недостающие ключи → один batch-запрос.
        let keys = ToolResultHydrationLogic.keysNeeded(messages: [message])
        #expect(keys == ["c1"])
        let results = try db.getToolResults(callIDs: keys)

        // 4. Применение возвращает текст.
        let hydrated = ToolResultHydrationLogic.apply(results: results, to: [message])
        guard case .toolCall(_, _, let result, _) = hydrated[0].parts[0] else {
            Issue.record("ожидался toolCall")
            return
        }
        #expect(result == "{\"ok\":true,\"data\":\"длинный результат\"}")
    }
}
