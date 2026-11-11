import Testing
import Foundation
@testable import myCoder

/// Потоковый аккумулятор вывода subprocess + чистые части git-publish
/// потока (one-time код, аргументы команд, описания ошибок).
@MainActor
@Suite("OutputAccumulator и GitPublishFlowLogic")
struct OutputAccumulatorGitPublishTests {

    @Test("oneTimeCode извлекает код вида XXXX-XXXX")
    func oneTimeCodeExtraction() {
        #expect(GitPublishFlowLogic.oneTimeCode(from: "Press Enter to open browser... code: 8A2F-4B9C") == "8A2F-4B9C")
        #expect(GitPublishFlowLogic.oneTimeCode(from: "нет кода") == nil)
    }

    @Test("createRepoArguments формирует публичный/приватный репозиторий")
    func createRepoArguments() {
        let pub = GitPublishFlowLogic.createRepoArguments(repoName: "demo", isPublic: true)
        #expect(pub.contains("repo") && pub.contains("create") && pub.contains("demo"))
        #expect(pub.contains("--public"))
        #expect(!pub.contains("--private"))

        let priv = GitPublishFlowLogic.createRepoArguments(repoName: "demo", isPublic: false)
        #expect(priv.contains("--private"))
    }

    @Test("OutputAccumulator: код сообщается ровно один раз")
    func accumulatorReportsCodeOnce() throws {
        let accumulator = OutputAccumulator()
        let first = accumulator.append("Some output\ncode: AB12-CD34\n")
        #expect(first == "AB12-CD34")
        // Повторный chunk с тем же кодом — повторного сигнала нет.
        let second = accumulator.append("again AB12-CD34\n")
        #expect(second == nil)
        #expect(accumulator.text.contains("AB12-CD34"))
    }

    @Test("OutputAccumulator: без кода — nil")
    func accumulatorNoCode() {
        let accumulator = OutputAccumulator()
        #expect(accumulator.append("just text") == nil)
        #expect(accumulator.text == "just text")
    }

    @Test("GitHubCLIError: человекочитаемые описания")
    func githubCLIErrorDescriptions() {
        #expect(GitHubCLIError.brewNotFound.errorDescription?.contains("Homebrew") == true)
        #expect(GitHubCLIError.commandFailed("boom").errorDescription == "boom")
    }
}
