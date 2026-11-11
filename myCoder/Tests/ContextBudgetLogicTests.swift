import Testing
import Foundation
@testable import myCoder

/// C6 (жалоба владельца 2026-11-09): «размер контекста чата не изменяется с
/// изменением модели или её параметров сразу после нового сообщения».
///
/// Причины, которые держат эти тесты:
///   1. ручной override контекста из «Параметров модели» игнорировался
///      бейджем — лимит брался только из ответа провайдера/каталога;
///   2. usage суммировал КАЖДЫЙ сохранённый `compiledContext`, а каждый пакет
///      уже содержит всю историю диалога — размер завышался в разы;
///   3. изменение параметров в настройках не будило чат — бейдж
///      пересчитывался только по случайному событию.
///
/// Здесь проверяется чистая логика, без UI: одна функция — один источник
/// правды для бейджа, авто-компакции и решения о смене модели.
@MainActor
@Suite("Бюджет контекста: пересчёт при смене модели/параметров (C6)")
struct ContextBudgetLogicTests {

    // MARK: - Fixtures

    /// Провайдер с одним/двумя моделями и явными лимитами.
    /// Вход: id провайдера, словарь modelID → context.
    /// Выход: `MimoProviderResponse` для чистых тестов.
    /// Зависимости: только модели приложения.
    private func provider(
        id: String = "provider-1",
        models: [String: Int?]
    ) -> MimoProviderResponse {
        var mapped: [String: MimoProviderModel] = [:]
        for (modelID, context) in models {
            mapped[modelID] = MimoProviderModel(
                id: modelID,
                providerID: id,
                limit: MimoModelLimit(context: context, output: nil)
            )
        }
        return MimoProviderResponse(id: id, name: id, models: mapped)
    }

    /// Сообщение с сохранённым пакетом контекста.
    /// Вход: текст запроса и текст пакета (auditText).
    /// Выход: user-сообщение с частью `.compiledContext`.
    /// Зависимости: `Message`, `MessagePartContent`.
    private func compiledUserMessage(
        _ request: String,
        pack: String
    ) -> Message {
        Message(
            role: .user,
            content: request,
            parts: [.text(request), .compiledContext(pack)],
            isFinished: true
        )
    }

    // MARK: - Лимит окна

    @Test("Override контекста из параметров модели побеждает провайдера")
    func overrideWinsOverProviderMetadata() {
        let providers = [provider(models: ["custom-model": 32_768])]
        let overrides = [
            ModelMetadataStore.key(providerID: "provider-1", modelID: "custom-model"):
                ModelMetadataOverride(context: 16_384)
        ]

        let limit = ContextBudgetLogic.effectiveContextLimit(
            modelID: "custom-model",
            providerID: "provider-1",
            serverProviders: providers,
            overrides: overrides
        )

        #expect(limit == 16_384, "ручной override контекста должен победить, got \(limit)")
    }

    @Test("Без override лимит берётся из метаданных провайдера")
    func providerMetadataUsedWithoutOverride() {
        let providers = [provider(models: ["custom-model": 32_768])]

        let limit = ContextBudgetLogic.effectiveContextLimit(
            modelID: "custom-model",
            providerID: "provider-1",
            serverProviders: providers,
            overrides: [:]
        )

        #expect(limit == 32_768)
    }

    @Test("Смена модели сразу меняет лимит и процент при тех же сообщениях")
    func modelSwitchChangesLimitImmediately() {
        let providers = [provider(models: [
            "model-small": 32_768,
            "model-large": 400_000,
        ])]
        let messages = [
            Message(role: .user,
                    content: String(repeating: "a", count: 40_000),
                    isFinished: true)
        ]

        let small = ContextBudgetLogic.usage(
            messages: messages,
            modelID: "model-small",
            providerID: "provider-1",
            serverProviders: providers,
            overrides: [:]
        )
        let large = ContextBudgetLogic.usage(
            messages: messages,
            modelID: "model-large",
            providerID: "provider-1",
            serverProviders: providers,
            overrides: [:]
        )

        #expect(small.limitTokens == 32_768)
        #expect(large.limitTokens == 400_000)
        #expect(small.usedTokens == large.usedTokens)
        #expect(small.percent != large.percent,
                "при смене модели процент должен пересчитаться сразу")
    }

    @Test("Смена override контекста сразу меняет процент")
    func overrideChangeRecalculatesPercentImmediately() {
        let providers = [provider(models: ["custom-model": 100_000])]
        let messages = [
            Message(role: .user,
                    content: String(repeating: "a", count: 40_000),
                    isFinished: true)
        ]

        let before = ContextBudgetLogic.usage(
            messages: messages,
            modelID: "custom-model",
            providerID: "provider-1",
            serverProviders: providers,
            overrides: [:]
        )
        let after = ContextBudgetLogic.usage(
            messages: messages,
            modelID: "custom-model",
            providerID: "provider-1",
            serverProviders: providers,
            overrides: [
                ModelMetadataStore.key(providerID: "provider-1", modelID: "custom-model"):
                    ModelMetadataOverride(context: 20_000)
            ]
        )

        #expect(before.limitTokens == 100_000)
        #expect(after.limitTokens == 20_000)
        #expect(after.percent > before.percent)
    }

    // MARK: - Использованные токены

    @Test("Новое сообщение сразу увеличивает использованные токены")
    func newMessageIncreasesUsageImmediately() {
        let providers = [provider(models: ["custom-model": 100_000])]
        let first = Message(role: .user, content: "hello", isFinished: true)

        let before = ContextBudgetLogic.usage(
            messages: [first],
            modelID: "custom-model",
            providerID: "provider-1",
            serverProviders: providers,
            overrides: [:]
        )
        let after = ContextBudgetLogic.usage(
            messages: [first, Message(role: .assistant,
                                      content: String(repeating: "b", count: 4_000),
                                      isFinished: true)],
            modelID: "custom-model",
            providerID: "provider-1",
            serverProviders: providers,
            overrides: [:]
        )

        #expect(after.usedTokens > before.usedTokens)
        #expect(after.usedTokens - before.usedTokens >= 1_000)
    }

    @Test("Каждый compiledContext содержит всю историю — считается только последний")
    func latestCompiledPayloadCountedOnce() {
        // Каждый пакет уже включает историю диалога, поэтому сумма всех
        // пакетов — многократный переучёт. Меряем последний пакет + хвост.
        let firstPack = String(repeating: "x", count: 20_000)
        let secondPack = String(repeating: "y", count: 20_000)
        let first = compiledUserMessage("first", pack: firstPack)
        let reply = Message(role: .assistant, content: "ok", isFinished: true)
        let second = compiledUserMessage("second", pack: secondPack)

        let usage = ContextBudgetLogic.usage(
            messages: [first, reply, second],
            modelID: "custom-model",
            providerID: "provider-1",
            serverProviders: [provider(models: ["custom-model": 100_000])],
            overrides: [:]
        )

        // `reply` стоит ДО последнего пакета и уже входит в его историю —
        // отдельно он не добавляется. Хвост после пакета пуст.
        let expected = ContextUsageLogic.tokensPerMessage
            + ContextUsageLogic.estimateTokens(secondPack)
        #expect(usage.usedTokens == expected,
                "ожидался ровно один последний пакет, got \(usage.usedTokens), expected \(expected)")
    }

    @Test("Без compiledContext usage считается по всем сообщениям")
    func fallsBackToAllMessagesWithoutCompiledContext() {
        let messages = [
            Message(role: .user, content: "hello", isFinished: true),
            Message(role: .assistant, content: "hi", isFinished: true),
        ]
        let usage = ContextBudgetLogic.usage(
            messages: messages,
            modelID: "custom-model",
            providerID: "provider-1",
            serverProviders: [provider(models: ["custom-model": 100_000])],
            overrides: [:]
        )
        #expect(usage.usedTokens == ContextUsageLogic.usedTokens(messages: messages))
    }

    // MARK: - Реактивность параметров

    @Test("ModelMetadataStore.set/clear шлют уведомление для немедленного пересчёта")
    func metadataChangePostsNotification() {
        let defaults = UserDefaults(suiteName: "com.mycoder.tests.metadata.\(UUID().uuidString)")!
        var received = 0
        let token = NotificationCenter.default.addObserver(
            forName: .modelMetadataChanged,
            object: nil,
            queue: nil
        ) { _ in received += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        ModelMetadataStore.set(
            ModelMetadataOverride(context: 32_768),
            providerID: "provider-1",
            modelID: "custom-model",
            defaults: defaults
        )
        #expect(received == 1, "set должен разбудить чат для пересчёта")

        ModelMetadataStore.clear(
            providerID: "provider-1",
            modelID: "custom-model",
            defaults: defaults
        )
        #expect(received == 2, "clear тоже должен разбудить чат")
    }
}
