import Testing
import Foundation
@testable import myCoder

/// Агентский цикл инструментов для API-пути (MiMo Serve): если ответ модели
/// содержит текстовые вызовы (DSML/```tool/Anthropic и т.п.), они
/// выполняются ПОСЛЕДОВАТЕЛЬНО, результаты собираются в один блок и
/// отправляются модели одним ответом; цикл повторяется до финального ответа.
@Suite("Агентский цикл инструментов (API-путь)")
struct AgentToolLoopLogicTests {

    private final class FakeExecutor {
        var calls: [WebToolCall] = []
        var results: [String: String] = [:]
        func execute(_ call: WebToolCall) async -> String {
            calls.append(call)
            return results[call.name] ?? "ok:\(call.name)"
        }
    }

    @Test("Несколько вызовов выполняются последовательно, результаты собираются в один блок")
    func sequentialCallsSingleResultBlock() async {
        let executor = FakeExecutor()
        let text = """
        <｜DSML｜ calls>
        <｜DSML｜ invoke name="list_dir">
        <｜DSML｜ parameter name="path" string="true">.</｜DSML｜ parameter>
        </｜DSML｜ invoke>
        <｜DSML｜ invoke name="glob">
        <｜DSML｜ parameter name="pattern" string="true">**/*.swift</｜DSML｜ parameter>
        </｜DSML｜ invoke>
        </｜DSML｜ calls>
        """
        var sentBlocks: [String] = []
        let result = await AgentToolLoopLogic.run(
            initialText: text,
            execute: { await executor.execute($0) },
            emitToolCall: { _, _ in },
            sendBack: { block in
                sentBlocks.append(block)
                return "Итоговый ответ модели"
            }
        )
        #expect(executor.calls.count == 2)
        #expect(executor.calls[0].name == "list_dir")
        #expect(executor.calls[1].name == "glob")
        // Один блок результатов: оба tool_result внутри.
        #expect(sentBlocks.count == 1)
        #expect(sentBlocks[0].contains("```tool_result"))
        #expect(sentBlocks[0].contains("list_dir"))
        #expect(sentBlocks[0].contains("glob"))
        // Финальный ответ — с результата sendBack.
        #expect(result.finalText == "Итоговый ответ модели")
    }

    @Test("Ответ без вызовов — сразу финал, без отправки")
    func finalAnswerWithoutCalls() async {
        var sentBlocks: [String] = []
        let result = await AgentToolLoopLogic.run(
            initialText: "Просто ответ.",
            execute: { _ in "" },
            emitToolCall: { _, _ in },
            sendBack: { block in
                sentBlocks.append(block)
                return ""
            }
        )
        #expect(sentBlocks.isEmpty)
        #expect(result.finalText == "Просто ответ.")
    }

    @Test("Цикл останавливается по лимиту итераций")
    func stopsAtIterationLimit() async {
        let executor = FakeExecutor()
        var iterations = 0
        let result = await AgentToolLoopLogic.run(
            initialText: "```tool\n{\"name\": \"grep\", \"args\": {\"pattern\": \"x\"}}\n```",
            maxIterations: 3,
            execute: { await executor.execute($0) },
            emitToolCall: { _, _ in },
            sendBack: { _ in
                iterations += 1
                // Модель снова зовёт тот же инструмент (зацикливание).
                return "```tool\n{\"name\": \"grep\", \"args\": {\"pattern\": \"x\"}}\n```"
            }
        )
        #expect(iterations == 3)
        #expect(result.iterationLimitReached)
    }

    @Test("На лимите итераций прописанные вызовы всё равно дают спойлер с причиной")
    func limitEmitsUnexecutedCalls() async {
        var emitted: [(String, String)] = []
        let result = await AgentToolLoopLogic.run(
            initialText: "```tool\n{\"name\": \"grep\", \"args\": {\"pattern\": \"x\"}}\n```",
            maxIterations: 1,
            execute: { _ in "ok" },
            emitToolCall: { call, text in emitted.append((call.name, text)) },
            sendBack: { _ in
                // Последний ответ модели содержит новый вызов, который уже
                // не будет исполнен.
                "```tool\n{\"name\": \"read_file\", \"args\": {\"path\": \"a\"}}\n```"
            }
        )
        #expect(result.iterationLimitReached)
        #expect(emitted.count == 2)
        #expect(emitted[0].0 == "grep")
        #expect(emitted[1].0 == "read_file")
        #expect(emitted[1].1.contains("iteration limit (1)"))
    }

    @Test("emitToolCall вызывается для каждого вызова с результатом")
    func emitsToolCalls() async {
        let executor = FakeExecutor()
        var emitted: [(String, String)] = []
        _ = await AgentToolLoopLogic.run(
            initialText: "```tool\n{\"name\": \"read_file\", \"args\": {\"path\": \"a.swift\"}}\n```",
            execute: { await executor.execute($0) },
            emitToolCall: { call, result in emitted.append((call.name, result)) },
            sendBack: { _ in "финал" }
        )
        #expect(emitted.count == 1)
        #expect(emitted[0].0 == "read_file")
        #expect(emitted[0].1 == "ok:read_file")
    }
}
