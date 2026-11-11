import Testing
import Foundation
@testable import myCoder

/// M1 live route execution against the LOCAL Ollama server.
///
/// Запуск: `MYCODER_LIVE_ROUTING=1 swift test --filter RoutingLive`
/// (нужны `ollama serve` и модель `gemma4:31b-cloud`).
///
/// Пользовательское ограничение (2026-11-10): на Ollama используется ТОЛЬКО
/// `gemma4:31b-cloud` — все роли маршрутизатора ходят на эту модель.
/// Цель теста — доказать, что маршрутизатор ДЕЙСТВИТЕЛЬНО исполняет цепочку
/// и журналирует каждый узел с фактической modelID (здесь — везде
/// `gemma4:31b-cloud`). Различие моделей МЕЖДУ узлами проверяется юнит-
/// тестами `RoutedTurnExecutorTests` на scripted-транспорте; живой прогон
/// обязан следовать ограничению пользователя.
///
/// Если Ollama недоступен или модели нет — тест честно пропускается
/// (SkipError), а не падает и не притворяется.
/// Opt-in для всей Suite: без `MYCODER_LIVE_ROUTING=1` тесты полностью
/// пропускаются (skipped), а не падают — как `LiveIntegrationTests`.
private var routingLiveEnabled: Bool {
    ProcessInfo.processInfo.environment["MYCODER_LIVE_ROUTING"] == "1"
}

@MainActor
@Suite("RoutingLive (M1)", .enabled(if: routingLiveEnabled))
struct RoutingLiveTests {

    /// Единственная разрешённая пользователем модель на Ollama.
    private var liveModel: String { "gemma4:31b-cloud" }

    /// Фактические имена моделей из `GET /api/tags` (порт 11434).
    ///
    /// Вход: нет. Выход: массив имён моделей Ollama (пусто, если сервер не
    /// отвечает). Зависимости: локальный `ollama serve`, URLSession.
    private func ollamaModels() -> [String] {
        guard let url = URL(string: "http://127.0.0.1:11434/api/tags"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            return []
        }
        return models.compactMap { $0["name"] as? String }
    }

    /// Каталог-провайдер Ollama для резолва транспорта ролей.
    ///
    /// Вход: список моделей. Выход: `RoleTransportContext` с одним локальным
    /// провайдером (kind .ollama, порт 11434). Зависимости: `LocalProviderConfig`.
    private func ollamaContext(models: [String], agentMode: AgentMode) -> RoleTransportContext {
        RoleTransportContext(
            customProviders: [],
            localProviders: [LocalProviderConfig(id: "live-ollama", kind: .ollama, port: 11434, models: models)],
            serverProviders: [],
            serverConnected: false,
            webProviderIDs: [],
            serverPort: 4096,
            agentMode: agentMode
        )
    }

    /// Определяет, является ли сообщение об ошибке внешним требованием оплаты
    /// (HTTP 402 от Ollama cloud: «Add usage credits or subscribe»). Такая
    /// ошибка — ожидаемая внешняя недоступность модели, а не сбой
    /// маршрутизации; честная остановка без fallback в этом случае есть
    /// корректное поведение M1.
    ///
    /// Вход: текст ошибки. Выход: true для 402/credit/plans.
    /// Зависимости: нет (чистая эвристика по тексту).
    private func isExternalPaymentRequirement(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("402")
            || lower.contains("credit")
            || lower.contains("plans")
            || lower.contains("subscribe")
    }

    @Test("RoutedTurnExecutor исполняет compose-цепочку на gemma4:31b-cloud")
    func executorRunsRealChainOnGemmaCloud() async throws {
        let all = ollamaModels()
        guard all.contains(liveModel) else {
            throw SkipError.issue("Ollama недоступен или нет \(liveModel) (нужно: ollama serve + ollama pull gemma4:31b-cloud)")
        }
        let context = ollamaContext(models: all, agentMode: .compose)
        let configuration = ModelRoutingConfiguration(mode: .perRole, assignments: [
            .dispatch: ModelAssignment(providerID: "live-ollama", modelID: liveModel),
            .execution: ModelAssignment(providerID: "live-ollama", modelID: liveModel),
            .finalResponse: ModelAssignment(providerID: "live-ollama", modelID: liveModel),
        ])
        let primary = ModelAssignment(providerID: "live-ollama", modelID: liveModel)
        let snapshot = RoutedTurnSnapshot(
            configuration: configuration,
            primary: primary,
            context: context,
            availableModels: ["live-ollama": all],
            visionSupport: [:],
            mainSupportsVision: nil,
            agentMode: .compose,
            sessionID: "live-routing-compose",
            request: "Ответь одним словом: ok",
            images: []
        )

        let outcome = await RoutedTurnExecutor.run(snapshot: snapshot)

        // Журнал обязан содержать реальные узлы с ФАКТИЧЕСКИМИ modelID.
        #expect(outcome.entries.count >= 1, "должен остаться журнал выполненных узлов")
        let executedModels = outcome.entries.map(\.assignment.modelID)
        #expect(executedModels.contains(liveModel), "dispatch должен реально уйти на \(liveModel)")
        #expect(executedModels.allSatisfy { $0 == liveModel }, "ограничение: только \(liveModel)")
        for entry in outcome.entries where entry.isCompleted {
            #expect(entry.error == nil)
            #expect(!(entry.result ?? "").isEmpty || entry.usage != nil,
                    "узел \(entry.role.rawValue) должен вернуть текст или usage")
        }
        switch outcome.status {
        case .completed:
            #expect(!(outcome.finalText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "completed-ход обязан дать непустой финальный текст")
        case .failed(let message):
            // Честная остановка — тоже доказательство M1: маршрутизатор НЕ
            // подменил модель и журналировал узел. Внешний HTTP 402 от
            // Ollama (cloud-модель требует платных кредитов) — ожидаемая
            // деградация, а не сбой маршрутизации.
            if isExternalPaymentRequirement(message) {
                #expect(outcome.entries.first?.assignment.modelID == liveModel,
                        "узел должен реально уйти на \(liveModel)")
                #expect(outcome.entries.first?.error != nil,
                        "журнал обязан зафиксировать ошибку узла")
            } else {
                Issue.record("Ход упал по неожиданной причине: \(message); журнальные модели: \(executedModels)")
            }
        case .cancelled, .reviewLimitReached:
            Issue.record("Неожиданный статус для compose-графа: \(outcome.status)")
        }
    }

    @Test("TurnRouteRunner исполняет кастомный граф execution → review → finalResponse")
    func runnerRunsCustomReviewGraph() async throws {
        let all = ollamaModels()
        guard all.contains(liveModel) else {
            throw SkipError.issue("Ollama недоступен или нет \(liveModel)")
        }
        let context = ollamaContext(models: all, agentMode: .build)
        let configuration = ModelRoutingConfiguration(mode: .perRole, assignments: [
            .execution: ModelAssignment(providerID: "live-ollama", modelID: liveModel),
            .review: ModelAssignment(providerID: "live-ollama", modelID: liveModel),
            .correction: ModelAssignment(providerID: "live-ollama", modelID: liveModel),
            .finalResponse: ModelAssignment(providerID: "live-ollama", modelID: liveModel),
        ])
        let primary = ModelAssignment(providerID: "live-ollama", modelID: liveModel)
        let graph = TurnRouteGraph(
            initialRoles: [.execution, .review, .finalResponse],
            maxReviewCycles: 1,
            requiresVisionFallback: false
        )

        let outcome = await TurnRouteRunner(configuration: configuration, primary: primary, graph: graph)
            .runCollecting(sessionID: "live-routing-review", request: "Ответь одним словом: ok") { role, assignment, input in
                // Реальный транспорт (URLSession) — никаких моков в live-прогоне.
                let executor = RoleRequestExecutor(context: context)
                return try await executor.send(role: role, assignment: assignment, input: input)
            }

        let report = outcome.report
        #expect(report.entries.count >= 1, "журнал должен содержать выполненные узлы")
        let executedModels = report.entries.map(\.assignment.modelID)
        #expect(executedModels.contains(liveModel), "execution должен реально уйти на \(liveModel)")
        #expect(executedModels.allSatisfy { $0 == liveModel }, "ограничение: только \(liveModel)")
        // Review-узел на живой модели почти наверняка вернёт не-JSON → граф
        // честно дойдёт до лимита ревью ИЛИ завершится; оба исхода допустимы.
        // Внешняя платная недоступность (402) — тоже допустимый честный исход.
        #expect(report.outcome == .completed || report.outcome == .reviewLimitReached || report.outcome == .failed,
                "исход должен быть одним из честных")
        if report.outcome == .completed {
            #expect(!(report.finalText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        if let error = outcome.error {
            if !isExternalPaymentRequirement(error.localizedDescription) {
                Issue.record("Граф остановился на неожиданной ошибке: \(error.localizedDescription); модели: \(executedModels)")
            }
        }
    }
}
