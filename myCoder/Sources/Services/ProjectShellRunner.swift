import Foundation

/// Runs a shell command as a real, bounded process (E12 — Раздел 12 п.18).
/// Captures stdout + stderr and returns a combined result with the exit code,
/// so gated commands at `.fullAccess` genuinely execute instead of returning a
/// canned "requires approval" message. Timeout-bounded so a hanging command
/// cannot stall the agentic loop.
struct ProjectShellResult: Equatable {
    let output: String
    let exitCode: Int32
}

enum ProjectShellRunner {
    /// Default shell used for command execution (/bin/zsh, matching the app's
    /// terminal panel). Executes with `-c` so multi-command pipelines work.
    static let shellPath = "/bin/zsh"
    static let defaultTimeoutSeconds: TimeInterval = 30

    /// Runs `command` in `workingDirectory`, capturing combined stdout/stderr.
    /// Terminates the process when it exceeds `timeoutSeconds`.
    static func run(command: String,
                    workingDirectory: String,
                    timeoutSeconds: TimeInterval = ProjectShellRunner.defaultTimeoutSeconds) -> ProjectShellResult {
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ProjectShellResult(output: "error: empty command", exitCode: 2)
        }
        // Audit A5: даже Full access не должен исполнять катастрофические команды
        // (rm -rf /, форматирование, перезагрузка, fork-бомбы).
        if let reason = DestructiveCommandGuard.blockReason(for: command) {
            return ProjectShellResult(output: "error: \(reason)", exitCode: 2)
        }
        let r = BoundedProcessRunner.run(executable: shellPath,
                                         arguments: ["-c", command],
                                         workingDirectory: workingDirectory,
                                         timeout: timeoutSeconds)
        if let launchError = r.launchError {
            return ProjectShellResult(output: "error: \(launchError)", exitCode: -1)
        }
        if r.timedOut {
            return ProjectShellResult(output: "error: command timed out after \(Int(timeoutSeconds))s", exitCode: 124)
        }
        var lines = r.output
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.isEmpty }
        if r.truncated { lines.append("[output truncated at 1 MB per stream]") }
        if r.exitCode != 0 { lines.append("(exit \(r.exitCode))") }
        return ProjectShellResult(output: lines.joined(separator: "\n"), exitCode: r.exitCode)
    }

    /// Проверяет команду перед исполнением и возвращает готовую ошибку, если
    /// выполнять её нельзя. nil означает «можно запускать».
    ///
    /// Вход: команда, рабочий каталог и функция вызова внутренней модели
    /// (в тестах — подставная). Выход: результат-блокировка или nil.
    /// Зависимости: `DangerousCommandAnalyzer`.
    static func safetyBlock(
        command: String,
        workingDirectory: String,
        completion: ([DirectChatMessage]) async throws -> String = { messages in
            try await InternalModelRunner.complete(
                messages: messages,
                timeout: DangerousCommandAnalyzer.reviewTimeout
            )
        }
    ) async -> ProjectShellResult? {
        switch await DangerousCommandAnalyzer.evaluate(
            command: command,
            workingDirectory: workingDirectory,
            completion: completion
        ) {
        case .allowed:
            return nil
        case .blocked(let reason):
            return ProjectShellResult(output: "error: \(reason)", exitCode: 2)
        case .notReviewed(let reason):
            return ProjectShellResult(
                output: "error: команда может изменить файлы или систему, но проверка внутренней моделью недоступна (\(reason)); команда не выполнена",
                exitCode: 2
            )
        }
    }
}
