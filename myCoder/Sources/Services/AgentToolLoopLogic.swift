import Foundation

/// Агентский цикл инструментов для API-пути (MiMo Serve) и других потоков,
/// где ответ модели приходит как простой текст без серверных tool-calls.
///
/// Если текст ответа содержит вызовы инструментов в любом из поддерживаемых
/// форматов (DSML, ```tool, Anthropic function_calls, function_call XML,
/// unfenced JSON и т.д.), они:
/// 1. выполняются ПОСЛЕДОВАТЕЛЬНО (один за другим);
/// 2. результаты собираются в ОДИН блок ```tool_result;
/// 3. блок отправляется модели одним ответом через `sendBack`;
/// 4. цикл повторяется до финального ответа без вызовов (или лимита).
enum AgentToolLoopLogic {

    struct Result: Equatable, Sendable {
        let finalText: String
        let iterationLimitReached: Bool
    }

    static func run(
        initialText: String,
        maxIterations: Int = 10,
        execute: @escaping (WebToolCall) async -> String,
        emitToolCall: @escaping (WebToolCall, String) async -> Void,
        sendBack: @escaping (String) async throws -> String
    ) async -> Result {
        var text = initialText
        for iteration in 0..<maxIterations {
            let calls = WebToolProtocolEmulator.parseToolCalls(from: text)
            guard !calls.isEmpty else {
                return Result(finalText: text, iterationLimitReached: false)
            }

            // Считаем вызовы одного ответа и собираем их результаты в ОДИН
            // блок: модель получает один ответ со всеми tool_result, а не
            // отдельный запрос на каждый вызов.
            var results: [(name: String, result: String)] = []
            results.reserveCapacity(calls.count)
            for call in calls {
                let result = await execute(call)
                await emitToolCall(call, result)
                results.append((name: call.name, result: result))
            }
            let resultsBlock = WebToolProtocolEmulator.formatToolResults(results)

            do {
                text = try await sendBack(resultsBlock)
            } catch {
                // Не удалось отправить результат — отдаём текущий текст как
                // финальный, чтобы чат не завис молча.
                return Result(finalText: text, iterationLimitReached: false)
            }

            if iteration == maxIterations - 1 {
                // Модель могла прописать новые вызовы в последнем ответе —
                // они уже не исполнятся, но обязаны попасть под спойлер с
                // причиной, а не исчезнуть.
                let pending = WebToolProtocolEmulator.parseToolCalls(from: text)
                for call in pending {
                    await emitToolCall(call, ToolCallSkipReason.iterationLimit(maxIterations).text)
                }
                return Result(finalText: text, iterationLimitReached: true)
            }
        }
        return Result(finalText: text, iterationLimitReached: true)
    }
}
