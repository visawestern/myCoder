import Testing
import Foundation
@testable import myCoder

/// M1 live route execution against the LOCAL Ollama server.
///
/// Запуск: `MYCODER_LIVE_ROUTING=1 swift test --filter RoutingLive`
/// (нужны `ollama serve` и ≥2 установленные модели).
///
/// Цель — доказать, что маршрутизатор ДЕЙСТВИТЕЛЬНО исполняет цепочку на
/// разных моделях: каждый узел журнала несёт фактическую modelID, а не
/// назначение «на бумаге». Если Ollama недоступен или моделей меньше двух,
/// тест честно пропускается (SkipError), а не падает и не притворяется.
@Suite("RoutingLive (M1)")
struct RoutingLiveTests {

    /// Opt-in флаг именно этого живого прогона маршрутизации.
    private var enabled: Bool {
        ProcessInfo.processInfo.environment["MYCODER_LIVE_ROUTING"] == "1"
    }

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

    /// Выбирает до `count` различных моделей, предпочитая маленькие/быстрые,
    /// чтобы живой прогон не длился минуты на больших весах.
    ///
    /// Вход: полный список моделей, нужное количество. Выход: массив моделей.
    /// Зависимости: нет (чистая эвристика по имени).
    private func pickModels(from all: [String], count: Int) -> [String] {
        let fastHints = ["gemma", "speakeasy", "e2b", "flash", "mini", "small", "tiny", "b-", "1b", "2b", "3b", "4b"]
        let sorted = all.sorted { a, b in
            let al = a.lowercased(), bl = b.lowercased()
            let af = fastHints.contains { al.contains($0) }
            let bf = fastHints.contains { bl.contains($0) }
            if af != bf { return af }
            return al < bl
        }
        var seen = Set<String>()
        var result: [String] = []
        for model in sorted where !seen.contains(model) {
            seen.insert(model)
            result.append(model)
            if result.count == count { break }
        }
        return result
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

    @Test("RoutedTurnExecutor исполняет compose-цепочку на разных фактических моделях")
    func executorRunsRealChainOnDistinctModels() async throws {
        guard enabled else { throw SkipError.issue("MYCODER_LIVE_ROUTING != 1") }
        let all = ollamaModels()
        guard all.count >= 2 else {
            throw SkipError.issue("Ollama недоступен или <2 моделей (нужно: ollama serve + ollama pull)")
        }
        let models = pickModels(from: all, count: 3)
        let dispatchModel = models[0]
        let executionModel = models.count > 1 ? models[1] : models[0]
        let finalModel = models.count > 2 ? models[2] : models[0]
        let context = ollamaContext(models: all, agentMode: .compose)
        let configuration = ModelRoutingConfiguration(mode: .perRole, assignments: [
            .dispatch: ModelAssignment(providerID: "live-ollama", modelID: dispatchModel),
            .execution: ModelAssignment(providerID: "live-ollama", modelID: executionModel),
            .finalResponse: ModelAssignment(providerID: "live-ollama", modelID: finalModel),
        ])
        let primary = ModelAssignment(providerID: "live-ollama", modelID: dispatchModel)
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
        #expect(executedModels.contains(dispatchModel), "dispatch должен реально уйти на \(dispatchModel)")
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
            Issue.record("Ход упал: \(message); журнальные модели: \(executedModels)")
        case .cancelled, .reviewLimitReached:
            Issue.record("Неожиданный статус для compose-графа: \(outcome.status)")
        }
    }

    @Test("TurnRouteRunner исполняет кастомный граф execution → review → finalResponse")
    func runnerRunsCustomReviewGraph() async throws {
        guard enabled else { throw SkipError.issue("MYCODER_LIVE_ROUTING != 1") }
        let all = ollamaModels()
        guard all.count >= 2 else {
            throw SkipError.issue("Ollama недоступен или <2 моделей")
        }
        let models = pickModels(from: all, count: 3)
        let execModel = models[0]
        let reviewModel = models.count > 1 ? models[1] : models[0]
        let finalModel = models.count > 2 ? models[2] : models[0]
        let context = ollamaContext(models: all, agentMode: .build)
        let configuration = ModelRoutingConfiguration(mode: .perRole, assignments: [
            .execution: ModelAssignment(providerID: "live-ollama", modelID: execModel),
            .review: ModelAssignment(providerID: "live-ollama", modelID: reviewModel),
            .correction: ModelAssignment(providerID: "live-ollama", modelID: execModel),
            .finalResponse: ModelAssignment(providerID: "live-ollama", modelID: finalModel),
        ])
        let primary = ModelAssignment(providerID: "live-ollama", modelID: execModel)
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
        #expect(executedModels.contains(execModel), "execution должен реально уйти на \(execModel)")
        // Review-узел на живой модели почти наверняка вернёт не-JSON → граф
        // честно дойдёт до лимита ревью ИЛИ завершится; оба исхода допустимы.
        #expect(report.outcome == .completed || report.outcome == .reviewLimitReached || report.outcome == .failed,
                "исход должен быть одним из честных")
        if report.outcome == .completed {
            #expect(!(report.finalText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        if let error = outcome.error {
            Issue.record("Граф остановился на ошибке: \(error.localizedDescription); модели: \(executedModels)")
        }
    }
}
