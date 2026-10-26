import Testing
import Foundation
@testable import myCoder

/// Round 29 devil's advocate findings (2026-08-21).
///
/// R1 (HIGH): model-controlled git arguments (message/branch/remote/limit)
/// were interpolated raw into a `/bin/zsh -c <command>` invocation, so a
/// crafted `git_commit` message like `x" && touch pwned && echo "` executed
/// arbitrary shell beyond what the approved operation implies.
///
/// R2 (MED): grep returned exactly at the 100-match limit WITHOUT any
/// truncation warning (early return skipped the Round-28 warning logic).
///
/// R3 (MED): glob matched the pattern against lastPathComponent only, so any
/// pattern containing "/" (`src/*.swift`, `**/*.swift`) always answered
/// "(no matches)" — lying to the model about the project state.
@Suite("Round 29 — git arg injection, grep hit-limit warning, glob slash patterns")
struct DevilsAdvocateRound29Tests {

    private func makeRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-r29-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeExecutor(root: URL) -> ProjectWebToolExecutor {
        ProjectWebToolExecutor(projectRoot: root.path, accessLevel: .fullAccess)
    }

    private func runGit(_ args: [String], in root: URL) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = args
        p.currentDirectoryURL = root
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    // MARK: - R1: command builders neutralize shell metacharacters

    @Test("commit message with shell metacharacters is single-quote escaped")
    func commitMessageInjectionNeutralized() {
        let cmd = ProjectWebToolExecutor.gitCommitCommand(
            message: "x\" && touch pwned && echo \"",
            addAll: false)
        #expect(cmd.contains("'x\" && touch pwned && echo \"'"),
                "message must be wrapped in single quotes, got: \(cmd)")
        #expect(!cmd.contains("\"x\" &&"), "raw double-quote breakout must be gone, got: \(cmd)")
    }

    @Test("commit message containing single quotes round-trips safely")
    func commitMessageSingleQuoteEscaped() {
        let cmd = ProjectWebToolExecutor.gitCommitCommand(message: "it's fine", addAll: false)
        #expect(cmd.contains("'it'\\''s fine'"), "embedded ' must become '\\'' , got: \(cmd)")
    }

    @Test("branch names are quoted for create and checkout")
    func branchInjectionNeutralized() {
        let create = ProjectWebToolExecutor.gitBranchCommand(branch: "a; rm -rf ~", create: true)
        #expect(create.contains("'a; rm -rf ~'"), "got: \(create)")
        let checkout = ProjectWebToolExecutor.gitCheckoutCommand(branch: "$(touch pwned)")
        #expect(checkout.contains("'$(touch pwned)'"), "got: \(checkout)")
    }

    @Test("push/pull remote and branch are quoted")
    func remoteRefQuoted() {
        let push = ProjectWebToolExecutor.gitRemoteRefCommand("git push",
                                                              remote: "origin; evil",
                                                              branch: "main`id`")
        #expect(push.contains("'origin; evil'"), "got: \(push)")
        #expect(push.contains("'main`id`'"), "got: \(push)")
    }

    @Test("git log limit is sanitized to digits")
    func logLimitSanitized() {
        #expect(ProjectWebToolExecutor.gitLogCommand(limit: "10; touch pwned").hasSuffix("-10"))
        #expect(ProjectWebToolExecutor.gitLogCommand(limit: "abc").hasSuffix("-10"),
                "non-numeric limit falls back to 10")
        #expect(ProjectWebToolExecutor.gitLogCommand(limit: "25").hasSuffix("-25"))
    }

    // MARK: - R1 end-to-end: real repo proves no side-effect execution

    @Test("malicious commit message cannot spawn extra commands in a real repo")
    func maliciousCommitDoesNotExecuteSideEffects() async throws {
        let root = try makeRoot()
        let exec = makeExecutor(root: root)
        _ = await exec.execute(WebToolCall(name: "write_file",
                                           arguments: ["path": "README.md", "content": "# t"]))
        #expect(runGit(["init", "-q"], in: root) == 0, "git init must succeed")
        _ = runGit(["config", "user.email", "test@example.com"], in: root)
        _ = runGit(["config", "user.name", "tester"], in: root)

        let marker = root.appendingPathComponent("pwned.marker")
        let malicious = "msg\" && touch pwned.marker && echo \""
        let result = await exec.execute(WebToolCall(name: "git_commit",
                                                    arguments: ["message": malicious,
                                                                "addAll": "true"]))
        #expect(!FileManager.default.fileExists(atPath: marker.path),
                "injected side effect must NOT run; executor said: \(result)")

        let committed = ProjectShellRunner.run(command: "git log --format=%s -1",
                                               workingDirectory: root.path).output
        #expect(committed.contains("msg"), "literal message should reach git, got: \(committed)")
    }

    // MARK: - R2: grep hit-limit truncation warning

    @Test("grep warns when the 100-match limit is reached")
    func grepHitLimitWarning() async throws {
        let root = try makeRoot()
        let exec = makeExecutor(root: root)
        var body = ""
        for i in 1...150 { body += "needle line \(i)\n" }
        _ = await exec.execute(WebToolCall(name: "write_file",
                                           arguments: ["path": "big.txt", "content": body]))

        let g = await exec.execute(WebToolCall(name: "grep",
                                               arguments: ["pattern": "needle", "path": "."]))
        #expect(g.contains("Truncated"), "hit-limit must warn, got tail: \(g.suffix(120))")
        #expect(!g.contains("line 101"), "must show only first 100 matches")
        #expect(g.components(separatedBy: "needle line").count - 1 <= 100)
    }

    // MARK: - R3: glob patterns with slashes

    @Test("glob matches nested paths for src/*.swift style patterns")
    func globSlashPatternMatchesNested() async throws {
        let root = try makeRoot()
        let exec = makeExecutor(root: root)
        _ = await exec.execute(WebToolCall(name: "write_file",
                                           arguments: ["path": "src/main.swift", "content": "a"]))
        _ = await exec.execute(WebToolCall(name: "write_file",
                                           arguments: ["path": "src/util/helper.swift", "content": "b"]))
        let g = await exec.execute(WebToolCall(name: "glob",
                                               arguments: ["pattern": "src/*.swift", "path": "."]))
        #expect(g.contains("src/main.swift"), "got: \(g)")
        #expect(!g.contains("helper.swift"), "* must not cross / inside one segment, got: \(g)")
    }

    @Test("double-star glob spans directories")
    func globDoubleStarSpansDirectories() async throws {
        let root = try makeRoot()
        let exec = makeExecutor(root: root)
        _ = await exec.execute(WebToolCall(name: "write_file",
                                           arguments: ["path": "root.swift", "content": "a"]))
        _ = await exec.execute(WebToolCall(name: "write_file",
                                           arguments: ["path": "deep/nested/x.swift", "content": "b"]))
        let g = await exec.execute(WebToolCall(name: "glob",
                                               arguments: ["pattern": "**/*.swift", "path": "."]))
        #expect(g.contains("root.swift"), "got: \(g)")
        #expect(g.contains("deep/nested/x.swift"), "got: \(g)")
    }

    @Test("bare star pattern stays within the root directory level")
    func globBareStarStaysAtRootLevel() async throws {
        let root = try makeRoot()
        let exec = makeExecutor(root: root)
        _ = await exec.execute(WebToolCall(name: "write_file",
                                           arguments: ["path": "keep.swift", "content": "a"]))
        _ = await exec.execute(WebToolCall(name: "write_file",
                                           arguments: ["path": "sub/hidden.swift", "content": "b"]))
        let g = await exec.execute(WebToolCall(name: "glob",
                                               arguments: ["pattern": "*.swift", "path": "."]))
        #expect(g.contains("keep.swift"), "got: \(g)")
        #expect(!g.contains("sub/hidden.swift"), "got: \(g)")
    }

    @Test("glob caps results with an explicit truncation warning")
    func globCapsResultsWithWarning() async throws {
        let root = try makeRoot()
        let exec = makeExecutor(root: root)
        for i in 0..<520 {
            _ = await exec.execute(WebToolCall(name: "write_file",
                                               arguments: ["path": "gen_\(String(format: "%04d", i)).txt",
                                                           "content": "x"]))
        }
        let g = await exec.execute(WebToolCall(name: "glob",
                                               arguments: ["pattern": "gen_*.txt", "path": "."]))
        #expect(g.contains("Truncated"), "got tail: \(g.suffix(120))")
    }

    // MARK: - Quality pass: end-to-end injection proof beyond git_commit

    @Test("malicious checkout branch cannot spawn extra commands in a real repo")
    func maliciousCheckoutDoesNotExecuteSideEffects() async throws {
        let root = try makeRoot()
        let exec = makeExecutor(root: root)
        _ = await exec.execute(WebToolCall(name: "write_file",
                                           arguments: ["path": "README.md", "content": "# t"]))
        #expect(runGit(["init", "-q"], in: root) == 0)
        _ = runGit(["config", "user.email", "test@example.com"], in: root)
        _ = runGit(["config", "user.name", "tester"], in: root)
        _ = runGit(["add", "."], in: root)
        _ = runGit(["commit", "-qm", "init"], in: root)
        #expect(runGit(["branch", "b1"], in: root) == 0)

        let marker = root.appendingPathComponent("pwned_checkout.marker")
        let result = await exec.execute(WebToolCall(name: "git_checkout",
                                                    arguments: ["branch": "b1$(touch pwned_checkout.marker)"]))
        #expect(!FileManager.default.fileExists(atPath: marker.path),
                "command substitution in branch must NOT execute; got: \(result)")
        #expect(result.contains("b1"), "literal branch name should reach git, got: \(result)")
    }

    // MARK: - Quality pass: grep file-limit warning with zero matches

    @Test("grep reports file-limit truncation even when no matches were found")
    func grepFileLimitNoMatchesStillWarns() async throws {
        let root = try makeRoot()
        let exec = makeExecutor(root: root)
        for i in 0..<505 {
            _ = await exec.execute(WebToolCall(name: "write_file",
                                               arguments: ["path": "gen_\(String(format: "%04d", i)).txt",
                                                           "content": "unrelated \(i)"]))
        }
        let g = await exec.execute(WebToolCall(name: "grep",
                                               arguments: ["pattern": "NEVER_MATCHES_XYZ_42", "path": "."]))
        #expect(g.contains("(no matches)"), "got: \(g.suffix(160))")
        #expect(g.contains("Truncated"),
                "silent (no matches) over a truncated scan is a data lie, got: \(g)")
    }
}
