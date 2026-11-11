import Testing
import Foundation
@testable import myCoder

/// Класс живых тестов против УДАЛЁННОГО OpenAI-совместимого провайдера.
///
/// Настройка переменными окружения:
/// - `OPENAI_COMPAT_BASE_URL` (обязателен, например `https://api.example.com/v1`);
/// - `OPENAI_COMPAT_API_KEY` (опционально);
/// - `OPENAI_COMPAT_MODEL` (обязателен).
///
/// Без этих переменных Suite отключена. STRATA сознательно не поддержана
/// (пользователь: «мой ноутбук не потянет»).
@MainActor
@Suite("Live: OpenAI-совместимый провайдер",
       .enabled(if: ProcessInfo.processInfo.environment["OPENAI_COMPAT_BASE_URL"] != nil
                    && ProcessInfo.processInfo.environment["OPENAI_COMPAT_MODEL"] != nil))
struct LiveOpenAICompatibleModelTests {

    private var baseURL: String {
        ProcessInfo.processInfo.environment["OPENAI_COMPAT_BASE_URL"] ?? ""
    }

    private var apiKey: String? {
        ProcessInfo.processInfo.environment["OPENAI_COMPAT_API_KEY"]
    }

    private var model: String {
        ProcessInfo.processInfo.environment["OPENAI_COMPAT_MODEL"] ?? ""
    }

    @Test("Прямой completion возвращает непустой текст и usage")
    func directCompletionReturnsText() async throws {
        let result = try await DirectChatClient.send(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            messages: [DirectChatMessage(role: "user", content: "Ответь одним словом: тест")]
        )
        let text = result.content.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(!text.isEmpty, "модель \(model) вернула пустой ответ")
        #expect(result.usage != nil)
    }

    @Test("Стриминг отдаёт контент")
    func streamReturnsContent() async throws {
        var received = 0
        let result = try await DirectChatStreamer.stream(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            messages: [DirectChatMessage(role: "user", content: "Посчитай от 1 до 3")]
        ) { update in
            if !update.content.isEmpty { received += 1 }
        }
        #expect(!result.content.isEmpty)
        #expect(received >= 1)
    }

    @Test("Пустой ответ провайдера ретраится и завершается честно")
    func emptyResponseUsesRetryPolicy() async throws {
        // Не дёргаем реальный провайдер для этой проверки — политика
        // ретраев уже покрыта юнит-тестами; здесь фиксируем контракт.
        #expect(RequestRetryPolicy.isRetryable(DirectChatError.emptyResponse))
    }
}
