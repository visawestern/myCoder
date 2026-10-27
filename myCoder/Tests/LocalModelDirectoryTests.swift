import Testing
import Foundation
@testable import myCoder

@Suite("Локальные модели компилятора — каталог и раннер")
struct LocalModelDirectoryTests {

    private func provider(id: String = "p1",
                          kind: LocalProviderKind = .ollama,
                          enabled: Bool = true,
                          models: [String] = ["qwen3:8b", "qwen3:14b"]) -> LocalProviderConfig {
        LocalProviderConfig(id: id,
                            kind: kind,
                            name: nil,
                            host: "127.0.0.1",
                            port: kind == .ollama ? 11434 : 8399,
                            isEnabled: enabled,
                            models: models,
                            username: "",
                            openCodeProviderID: "opencode")
    }

    @Test("Кандидаты идут в порядке провайдеров и моделей как в настройках")
    func candidatesKeepConfiguredOrder() {
        let directory = LocalModelDirectoryBuilder.build(localProviders: [
            provider(id: "p1", models: ["a:3b", "b:7b"]),
            provider(id: "p2", kind: .strata, models: ["c:14b"])
        ])
        #expect(directory.candidates.map(\.model) == ["a:3b", "b:7b", "c:14b"])
        #expect(directory.candidates.map(\.providerID) == ["p1", "p1", "p2"])
        #expect(directory.candidates.first?.baseURL == "http://127.0.0.1:11434/v1")
        #expect(directory.candidates.last?.baseURL == "http://127.0.0.1:8399/v1")
    }

    @Test("Выключенные провайдеры и OpenCode-серверы не участвуют")
    func disabledAndSessionProvidersAreSkipped() {
        let directory = LocalModelDirectoryBuilder.build(localProviders: [
            provider(id: "off", enabled: false, models: ["x:3b"]),
            provider(id: "session", kind: .openCode, models: ["y:7b"]),
            provider(id: "on", kind: .strata, models: ["z:8b"])
        ])
        #expect(directory.candidates.map(\.model) == ["z:8b"])
    }

    @Test("Пустой каталог — пустой список кандидатов")
    func emptyDirectory() {
        #expect(LocalModelDirectoryBuilder.build(localProviders: []).candidates.isEmpty)
        #expect(LocalModelDirectoryBuilder.build(localProviders: [provider(models: [])]).candidates.isEmpty)
    }

    // MARK: - Runner

    /// Records which models were tried. A reference type so the test can
    /// observe the calls made through the `LocalCompilerTransporting` existential.
    private final class FakeTransport: LocalCompilerTransporting, @unchecked Sendable {
        let answers: [String: String]
        let failing: Set<String>
        private(set) var attempted: [String] = []

        init(answers: [String: String], failing: Set<String> = []) {
            self.answers = answers
            self.failing = failing
        }

        func complete(candidate: LocalModelCandidate, prompt: String, system: String?) async throws -> String {
            attempted.append(candidate.model)
            if failing.contains(candidate.model) {
                throw LocalCompilerError.transportFailed(model: candidate.model, reason: "unreachable")
            }
            guard let answer = answers[candidate.model] else {
                throw LocalCompilerError.transportFailed(model: candidate.model, reason: "no answer")
            }
            return answer
        }
    }

    @Test("Раннер берёт первую модель и возвращает её ответ")
    func runnerUsesFirstModel() async throws {
        let directory = LocalModelDirectoryBuilder.build(localProviders: [
            provider(models: ["a:3b", "b:7b"])
        ])
        let transport = FakeTransport(answers: ["a:3b": "ok-a"])
        let runner = LocalModelRunner(directory: directory, transport: transport)
        let result = try await runner.run(prompt: "p", system: nil)
        #expect(result.text == "ok-a")
        #expect(result.candidate.model == "a:3b")
        #expect(transport.attempted == ["a:3b"])
    }

    @Test("Упавшая модель — берётся следующая из списка")
    func runnerFallsToNextModel() async throws {
        let directory = LocalModelDirectoryBuilder.build(localProviders: [
            provider(models: ["a:3b", "b:7b", "c:14b"])
        ])
        let transport = FakeTransport(answers: ["c:14b": "ok-c"], failing: ["a:3b", "b:7b"])
        let runner = LocalModelRunner(directory: directory, transport: transport)
        let result = try await runner.run(prompt: "p", system: nil)
        #expect(result.text == "ok-c")
        #expect(result.candidate.model == "c:14b")
        #expect(transport.attempted == ["a:3b", "b:7b", "c:14b"])
    }

    @Test("Пустой ответ модели считается сбоем и переходит к следующей")
    func runnerSkipsEmptyAnswer() async throws {
        let directory = LocalModelDirectoryBuilder.build(localProviders: [
            provider(models: ["a:3b", "b:7b"])
        ])
        let transport = FakeTransport(answers: ["a:3b": "", "b:7b": "ok"])
        let runner = LocalModelRunner(directory: directory, transport: transport)
        let result = try await runner.run(prompt: "p", system: nil)
        #expect(result.text == "ok")
        #expect(result.candidate.model == "b:7b")
    }

    @Test("Когда не работает ни одна модель — типизированная ошибка")
    func runnerFailsWhenNoModelWorks() async {
        let directory = LocalModelDirectoryBuilder.build(localProviders: [
            provider(models: ["a:3b"])
        ])
        let transport = FakeTransport(answers: [:], failing: ["a:3b"])
        let runner = LocalModelRunner(directory: directory, transport: transport)
        await #expect(throws: LocalCompilerError.self) {
            _ = try await runner.run(prompt: "p", system: nil)
        }
    }

    @Test("Пустой каталог моделей даёт ошибку до сетевого вызова")
    func runnerFailsOnEmptyDirectory() async {
        let runner = LocalModelRunner(directory: LocalModelDirectoryBuilder.build(localProviders: []),
                                      transport: FakeTransport(answers: [:]))
        await #expect(throws: LocalCompilerError.self) {
            _ = try await runner.run(prompt: "p", system: nil)
        }
    }
}
