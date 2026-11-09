import Foundation

/// Единый источник правды для бюджета контекста модели (C6).
///
/// Зачем отдельный слой:
///   1. бейдж контекста, авто-компакция и решение о смене модели обязаны
///      считать ОДИН И ТОТ ЖЕ лимит — иначе чат компактится не тогда, когда
///      показывает бейдж;
///   2. ручной override контекста/выхода из «Параметров модели»
///      (`ModelMetadataStore`) должен применяться везде, а не только в
///      редакторе метаданных;
///   3. usage не должен суммировать каждый сохранённый `compiledContext`:
///      каждый пакет уже содержит всю историю диалога, поэтому сумма пакетов
///      завышает размер в разы.
///
/// Все функции чистые: параметры передаются явно, `UserDefaults` читается
/// только через значение по умолчанию у `overrides`.
enum ContextBudgetLogic {

    // MARK: - Лимиты окна

    /// Эффективное окно контекста модели.
    ///
    /// Вход: `modelID` — id модели; `providerID` — провайдер (nil = искать по
    /// всем); `serverProviders` — каталог провайдеров; `overrides` — ручные
    /// правки метаданных (по умолчанию из `ModelMetadataStore`).
    /// Выход: размер окна в токенах; при отсутствии данных — каталожный
    /// fallback (200k).
    /// Зависимости: `ProviderSettingsLogic.model`, `ModelMetadataResolver`,
    /// `ContextWindowCatalog`.
    static func effectiveContextLimit(
        modelID: String,
        providerID: String?,
        serverProviders: [MimoProviderResponse],
        overrides: [String: ModelMetadataOverride] = ModelMetadataStore.loadAll()
    ) -> Int {
        let resolved = resolvedMetadata(
            modelID: modelID,
            providerID: providerID,
            serverProviders: serverProviders,
            overrides: overrides
        )
        return ContextWindowCatalog.limit(for: modelID, reported: resolved?.limit?.context)
    }

    /// Эффективный лимит выхода модели (с учётом ручного override).
    ///
    /// Вход: те же, что у `effectiveContextLimit`.
    /// Выход: лимит completion в токенах (fallback 32k).
    /// Зависимости: `ProviderSettingsLogic.model`, `ModelMetadataResolver`,
    /// `ContextWindowCatalog`.
    static func effectiveOutputLimit(
        modelID: String,
        providerID: String?,
        serverProviders: [MimoProviderResponse],
        overrides: [String: ModelMetadataOverride] = ModelMetadataStore.loadAll()
    ) -> Int {
        let resolved = resolvedMetadata(
            modelID: modelID,
            providerID: providerID,
            serverProviders: serverProviders,
            overrides: overrides
        )
        return ContextWindowCatalog.outputLimit(for: modelID, reported: resolved?.limit?.output)
    }

    /// Метаданные модели с применённым ручным override.
    ///
    /// Вход: `modelID`, `providerID`, каталог провайдеров, карта overrides.
    /// Выход: `MimoProviderModel?` — провайдерские данные, дополненные
    /// override; nil, когда о модели нет вообще никаких данных.
    /// Зависимости: `ProviderSettingsLogic.model`, `ModelMetadataStore.key`,
    /// `ModelMetadataResolver`.
    private static func resolvedMetadata(
        modelID: String,
        providerID: String?,
        serverProviders: [MimoProviderResponse],
        overrides: [String: ModelMetadataOverride]
    ) -> MimoProviderModel? {
        let serverModel = ProviderSettingsLogic.model(
            for: modelID,
            in: serverProviders,
            providerID: providerID
        )
        let override = providerID.flatMap { id in
            overrides[ModelMetadataStore.key(providerID: id, modelID: modelID)]
        }
        return ModelMetadataResolver.resolve(
            modelID: modelID,
            providerID: providerID ?? "",
            serverModel: serverModel,
            override: override
        )
    }

    // MARK: - Usage

    /// Usage по уже отобранной model-bound истории и известному лимиту.
    ///
    /// Вход: `messages` — история, которую увидит модель; `limitTokens` —
    /// окно модели.
    /// Выход: `ContextUsage` (used/limit/percent).
    /// Зависимости: `usedTokens`.
    static func usage(messages: [Message], limitTokens: Int) -> ContextUsage {
        ContextUsage(usedTokens: usedTokens(messages: messages), limitTokens: limitTokens)
    }

    /// Usage с самостоятельным разрешением лимита по модели.
    ///
    /// Вход: `messages`, `modelID`, `providerID`, каталог провайдеров,
    /// карта overrides.
    /// Выход: `ContextUsage` — бейдж и авто-компакция получают одно число.
    /// Зависимости: `effectiveContextLimit`, `usage`.
    static func usage(
        messages: [Message],
        modelID: String,
        providerID: String?,
        serverProviders: [MimoProviderResponse],
        overrides: [String: ModelMetadataOverride] = ModelMetadataStore.loadAll()
    ) -> ContextUsage {
        usage(
            messages: messages,
            limitTokens: effectiveContextLimit(
                modelID: modelID,
                providerID: providerID,
                serverProviders: serverProviders,
                overrides: overrides
            )
        )
    }

    /// Токены, которые реально уйдут модели на следующем ходу.
    ///
    /// Вход: `messages` — model-bound история (после `historyForModel`).
    /// Выход: оценка в токенах.
    /// Зависимости: `ContextUsageLogic.estimateTokens`,
    /// `ContextUsageLogic.tokens(for:)`.
    ///
    /// Ключевое правило: каждый сохранённый `compiledContext` — это ПОЛНЫЙ
    /// пакет (system instruction + контекст + история + запрос). Поэтому
    /// старые пакеты не суммируются: берётся последний пакет как лучшая
    /// оценка следующего промпта, плюс сообщения после него. Без пакетов
    /// считается обычная сумма по сообщениям.
    static func usedTokens(messages: [Message]) -> Int {
        guard let index = messages.lastIndex(where: hasCompiledContext) else {
            return ContextUsageLogic.usedTokens(messages: messages)
        }

        let compiled = messages[index]
        var total = ContextUsageLogic.tokensPerMessage
        for part in compiled.parts {
            switch part {
            case .text, .compiledContext:
                // Текст запроса уже внутри пакета; сам пакет считаем отдельно
                // в ветке ниже, чтобы не потерять его размер.
                continue
            case .reasoning(let reasoning):
                total += ContextUsageLogic.estimateTokens(reasoning)
            case .toolCall(let name, let args, let result, _):
                total += ContextUsageLogic.estimateTokens(name)
                total += ContextUsageLogic.estimateTokens(args)
                if let result { total += ContextUsageLogic.estimateTokens(result) }
            case .image:
                total += ContextUsageLogic.tokensPerImage
            case .stepStart, .stepFinish, .routeInfo:
                break
            }
        }
        if let pack = compiled.parts.compactMap(compiledContextText).last {
            total += ContextUsageLogic.estimateTokens(pack)
        }
        for message in messages[(index + 1)...] {
            total += ContextUsageLogic.tokens(for: message)
        }
        return total
    }

    /// Есть ли у сообщения сохранённый пакет контекста.
    ///
    /// Вход: `message`.
    /// Выход: true, если среди частей есть `.compiledContext`.
    /// Зависимости: `MessagePartContent`.
    private static func hasCompiledContext(_ message: Message) -> Bool {
        message.parts.contains { part in
            if case .compiledContext = part { return true }
            return false
        }
    }

    /// Текст пакета из части сообщения.
    ///
    /// Вход: часть сообщения.
    /// Выход: текст пакета или nil для остальных частей.
    /// Зависимости: `MessagePartContent`.
    private static func compiledContextText(_ part: MessagePartContent) -> String? {
        if case .compiledContext(let text) = part { return text }
        return nil
    }
}
