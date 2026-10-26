import Testing
import Foundation
@testable import myCoder

@Suite("E12 — run_command gated by AccessLevel (Раздел 12 п.18): real execution at fullAccess, approval otherwise")
struct E12RunCommandGateTests {

    private func makeTempProjectDir(_ name: String = UUID().uuidString) throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mimo-e12-\(name)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    // MARK: - Access gate logic

    @Test("fullAccess allows run_command")
    func fullAccessAllowsCommand() {
        #expect(WebToolAccessGate.permission(for: runCommandCall(), accessLevel: .fullAccess) == .allow)
    }

    @Test("editAutomatically and askBeforeChanges require approval for a mutating run_command")
    func lowerLevelsRequireApproval() {
        // A mutating command (here: touch) must be gated below fullAccess.
        let mutating = WebToolCall(name: "run_command", arguments: ["command": "touch x.txt"])
        #expect(WebToolAccessGate.permission(for: mutating, accessLevel: .editAutomatically) == .requireApproval)
        #expect(WebToolAccessGate.permission(for: mutating, accessLevel: .askBeforeChanges) == .requireApproval)
        // A read-only command (ls) is allowed at every level.
        #expect(WebToolAccessGate.permission(for: runCommandCall(), accessLevel: .editAutomatically) == .allow)
        #expect(WebToolAccessGate.permission(for: runCommandCall(), accessLevel: .askBeforeChanges) == .allow)
    }

    @Test("read-only tools never require approval at any level")
    func readOnlyToolsAlwaysAllowed() {
        let read = WebToolCall(name: "read_file", arguments: ["path": "a.txt"])
        #expect(WebToolAccessGate.permission(for: read, accessLevel: .askBeforeChanges) == .allow)
        let list = WebToolCall(name: "list_dir", arguments: ["path": "."])
        #expect(WebToolAccessGate.permission(for: list, accessLevel: .askBeforeChanges) == .allow)
        let grep = WebToolCall(name: "grep", arguments: ["pattern": "x", "path": "."])
        #expect(WebToolAccessGate.permission(for: grep, accessLevel: .askBeforeChanges) == .allow)
    }

    // MARK: - Real execution

    @Test("run_command executes for real at fullAccess and returns stdout")
    func commandExecutesAtFullAccess() async throws {
        let root = try makeTempProjectDir()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let exec = ProjectWebToolExecutor(projectRoot: root, accessLevel: .fullAccess)

        let result = await exec.execute(WebToolCall(name: "run_command", arguments: ["command": "echo hello-e12"]))
        #expect(result.contains("hello-e12"), "real stdout must be returned, got: \(result)")
    }

    @Test("run_command runs with the project directory as cwd")
    func commandRunsInProjectDirectory() async throws {
        let root = try makeTempProjectDir()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try "marker".write(toFile: (root as NSString).appendingPathComponent("cwd-marker.txt"),
                           atomically: true, encoding: .utf8)
        let exec = ProjectWebToolExecutor(projectRoot: root, accessLevel: .fullAccess)

        let result = await exec.execute(WebToolCall(name: "run_command", arguments: ["command": "cat cwd-marker.txt"]))
        #expect(result.contains("marker"), "command must resolve relative paths against projectRoot")
    }

    @Test("run_command gated at editAutomatically returns approval message, does not execute")
    func commandGatedAtEditAutomatically() async throws {
        let root = try makeTempProjectDir()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let exec = ProjectWebToolExecutor(projectRoot: root, accessLevel: .editAutomatically)

        // A command that would create a file must NOT run at this level.
        let result = await exec.execute(WebToolCall(name: "run_command", arguments: ["command": "touch should-not-exist.txt"]))
        #expect(result.contains("approval"))
        #expect(!FileManager.default.fileExists(atPath: (root as NSString).appendingPathComponent("should-not-exist.txt")),
                "gated command must not execute")
    }

    @Test("run_command gated at askBeforeChanges returns approval message, does not execute")
    func commandGatedAtAskBeforeChanges() async throws {
        let root = try makeTempProjectDir()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let exec = ProjectWebToolExecutor(projectRoot: root, accessLevel: .askBeforeChanges)

        let result = await exec.execute(WebToolCall(name: "run_command", arguments: ["command": "touch nope.txt"]))
        #expect(result.contains("approval"))
        #expect(!FileManager.default.fileExists(atPath: (root as NSString).appendingPathComponent("nope.txt")))
    }

    @Test("default access level (no explicit value) gates run_command")
    func defaultLevelGatesCommand() async throws {
        let root = try makeTempProjectDir()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let exec = ProjectWebToolExecutor(projectRoot: root) // default = askBeforeChanges

        let result = await exec.execute(WebToolCall(name: "run_command", arguments: ["command": "touch no.txt"]))
        #expect(result.contains("approval"))
    }

    @Test("failing command surfaces its error output at fullAccess")
    func failingCommandSurfacesError() async throws {
        let root = try makeTempProjectDir()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let exec = ProjectWebToolExecutor(projectRoot: root, accessLevel: .fullAccess)

        let result = await exec.execute(WebToolCall(name: "run_command", arguments: ["command": "echo to-stderr 1>&2; exit 3"]))
        #expect(result.contains("to-stderr"), "stderr must be captured, got: \(result)")
        #expect(result.contains("3"), "exit code must be surfaced")
    }

    private func runCommandCall() -> WebToolCall {
        WebToolCall(name: "run_command", arguments: ["command": "ls"])
    }
}
