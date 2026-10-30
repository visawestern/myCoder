import Testing
import Foundation
@testable import myCoder

/// Класс живых тестов против ЛОКАЛЬНОЙ модели (Ollama).
///
/// Запуск: `MIMO_LIVE_TESTS=1 swift test --filter LiveLocalOllamaModelTests`
/// Модель берётся из `OLLAMA_MODEL` (по умолчанию `gemma4:31b-cloud`).
/// Если Ollama недоступен или модель не загружена — тесты сообщают об
/// этом честно (skip с причиной), а не падают.
@Suite("Live: локальная модель (Ollama)",
       .enabled(if: liveTestsEnabled))
struct LiveLocalOllamaModelTests {

    private var model: String {
        ProcessInfo.processInfo.environment["OLLAMA_MODEL"] ?? "gemma4:31b-cloud"
    }

    private var baseURL: String { "http://127.0.0.1:11434/v1" }

    @Test("Ollama доступен и модель загружена")
    func ollamaIsReachableWithModel() {
        guard ollamaReachable(modelContaining: String(model.split(separator: ":").first ?? "")) else {
            Issue.record("Ollama недоступен или модель '\(model)' не загружена (ollama pull \(model))")
            return
        }
    }

    @Test("Прямой completion через OpenAI-совместимый endpoint возвращает текст")
    func directCompletionReturnsText() async throws {
        guard ollamaReachable(modelContaining: String(model.split(separator: ":").first ?? "")) else {
            throw SkipError.issue("Ollama или модель недоступны")
        }
        let result = try await DirectChatClient.send(
            baseURL: baseURL,
            apiKey: nil,
            model: model,
            messages: [DirectChatMessage(role: "user", content: "Ответь одним словом: тест")]
        )
        #expect(!result.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(result.usage != nil)
    }

    @Test("Пульс стриминга отдаёт хотя бы один апдейт")
    func streamEmitsUpdate() async throws {
        guard ollamaReachable(modelContaining: String(model.split(separator: ":").first ?? "")) else {
            throw SkipError.issue("Ollama или модель недоступны")
        }
        var updates = 0
        let result = try await DirectChatStreamer.stream(
            baseURL: baseURL,
            apiKey: nil,
            model: model,
            messages: [DirectChatMessage(role: "user", content: "Посчитай от 1 до 3")]
        ) { update in
            if !update.content.isEmpty { updates += 1 }
        }
        #expect(!result.content.isEmpty)
        #expect(updates >= 1)
    }
}

/// Минимальная ошибка-пропуск для живых тестов.
enum SkipError: Error {
    case issue(String)
}

extension SkipError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .issue(let reason): return "пропущено: \(reason)"
        }
    }
}
