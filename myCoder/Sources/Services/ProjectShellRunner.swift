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
}
