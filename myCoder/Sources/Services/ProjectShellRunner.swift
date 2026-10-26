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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = ["-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return ProjectShellResult(output: "error: failed to launch: \(error.localizedDescription)", exitCode: -1)
        }

        // Wait for completion, then terminate on timeout (like the terminal
        // panel's deadline loop) so runaway commands cannot hang the loop.
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning {
            if Date() > deadline {
                process.terminate()
                process.waitUntilExit()
                return ProjectShellResult(output: "error: command timed out after \(Int(timeoutSeconds))s", exitCode: 124)
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        let outData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let outText = String(data: outData, encoding: .utf8) ?? ""
        let errText = String(data: errData, encoding: .utf8) ?? ""

        var lines: [String] = []
        let combined = (outText + errText)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        for line in combined where !line.isEmpty {
            lines.append(line)
        }
        if process.terminationStatus != 0 {
            lines.append("(exit \(process.terminationStatus))")
        }
        return ProjectShellResult(output: lines.joined(separator: "\n"), exitCode: process.terminationStatus)
    }
}
