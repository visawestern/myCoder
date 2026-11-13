import Foundation
import Testing
@testable import myCoder

/// TDD for the pre-write module budget (directive 2026-11-13): every code
/// edit must leave the file at or below 600 physical lines. The guard rejects
/// the mutation before any disk write and tells the model to split the file
/// logically and update its references.
@MainActor
@Suite("File length guard — 600-line module budget on every code edit")
struct FileLengthGuardTests {

    private func makeRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-length-guard-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeExecutor(root: URL) -> ProjectWebToolExecutor {
        ProjectWebToolExecutor(projectRoot: root.path, accessLevel: .fullAccess)
    }

    /// Build text with exactly `lines` physical lines (newline terminated).
    private func source(lines: Int, token: String = "let value = 1") -> String {
        (0..<lines).map { _ in token }.joined(separator: "\n") + "\n"
    }

    private func physicalLines(_ text: String) -> Int {
        text.utf8.reduce(0) { $1 == 0x0A ? $0 + 1 : $0 }
    }

    @Test func sourceExtensionsAreCoveredAndDocsAreNot() {
        #expect(FileLengthGuardLogic.isSourceFile("Sources/App.swift"))
        #expect(FileLengthGuardLogic.isSourceFile("web/app.TSX"))
        #expect(FileLengthGuardLogic.isSourceFile("scripts/build.py"))
        #expect(FileLengthGuardLogic.isSourceFile("cmd/server.go"))
        #expect(!FileLengthGuardLogic.isSourceFile("docs/PLAN.md"))
        #expect(!FileLengthGuardLogic.isSourceFile("package.json"))
        #expect(!FileLengthGuardLogic.isSourceFile("Makefile"))
    }

    @Test func refusalNamesThePathTheLimitAndTheRequiredSplit() throws {
        let text = source(lines: 601)
        let refusal = try #require(
            FileLengthGuardLogic.refusal(action: "write_file", path: "Sources/Big.swift", content: text)
        )
        #expect(refusal.contains("Sources/Big.swift"))
        #expect(refusal.contains("601"))
        #expect(refusal.contains("600"))
        #expect(refusal.lowercased().contains("split"))
        #expect(refusal.lowercased().contains("references"))
    }

    @Test func atLimitIsAllowed() {
        #expect(FileLengthGuardLogic.refusal(
            action: "write_file", path: "Sources/Exact.swift", content: source(lines: 600)
        ) == nil)
    }

    @Test func writeFileOverLimitIsRejectedBeforeAnyWrite() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let exec = makeExecutor(root: root)

        let result = await exec.execute(WebToolCall(
            name: "write_file",
            arguments: ["path": "Sources/Big.swift", "content": source(lines: 601)]
        ))

        #expect(result.hasPrefix("error:"))
        #expect(result.contains("600"))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources/Big.swift").path))
    }

    @Test func writeFileAtLimitIsWritten() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let exec = makeExecutor(root: root)

        let result = await exec.execute(WebToolCall(
            name: "write_file",
            arguments: ["path": "Sources/Exact.swift", "content": source(lines: 600)]
        ))

        #expect(result.hasPrefix("ok"))
        let written = try String(
            contentsOf: root.appendingPathComponent("Sources/Exact.swift"),
            encoding: .utf8
        )
        #expect(physicalLines(written) == 600)
    }

    @Test func nonSourceFileMayExceedTheBudget() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let exec = makeExecutor(root: root)

        let result = await exec.execute(WebToolCall(
            name: "write_file",
            arguments: ["path": "docs/LONG.md", "content": source(lines: 601, token: "line")]
        ))

        #expect(result.hasPrefix("ok"))
    }

    @Test func editThatPushesASourceFileOverTheLimitIsRejectedAndLeavesItUntouched() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let exec = makeExecutor(root: root)

        let original = "// header\n" + source(lines: 589)
        #expect(physicalLines(original) == 590)
        let write = await exec.execute(WebToolCall(
            name: "write_file",
            arguments: ["path": "Sources/Grow.swift", "content": original]
        ))
        #expect(write.hasPrefix("ok"))

        let addition = (0..<20).map { "let extra\($0) = \($0)" }.joined(separator: "\n")
        let edit = await exec.execute(WebToolCall(
            name: "edit_file",
            arguments: ["path": "Sources/Grow.swift", "old": "// header", "new": "// header\n" + addition]
        ))

        #expect(edit.hasPrefix("error:"))
        #expect(edit.contains("610"))
        let onDisk = try String(
            contentsOf: root.appendingPathComponent("Sources/Grow.swift"),
            encoding: .utf8
        )
        #expect(onDisk == original)
    }

    @Test func editThatReducesAnOverLimitSourceFileBackUnderBudgetIsAllowed() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let exec = makeExecutor(root: root)

        let block = (0..<60).map { "let old\($0) = \($0)" }.joined(separator: "\n")
        let oversized = "// header\n" + block + "\n" + source(lines: 589)
        #expect(physicalLines(oversized) == 650)
        // Seed the oversized file directly: the guard is about edits, and the
        // fixture must start from a state the guard itself would refuse.
        let legacyURL = root.appendingPathComponent("Sources/Legacy.swift")
        try FileManager.default.createDirectory(
            at: legacyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try oversized.write(to: legacyURL, atomically: true, encoding: .utf8)

        let edit = await exec.execute(WebToolCall(
            name: "edit_file",
            arguments: ["path": "Sources/Legacy.swift", "old": block, "new": "// compact"]
        ))

        #expect(edit.hasPrefix("ok"))
        let onDisk = try String(
            contentsOf: root.appendingPathComponent("Sources/Legacy.swift"),
            encoding: .utf8
        )
        #expect(physicalLines(onDisk) == 591)
    }

    @Test func editToANonSourceFileIsNotGuarded() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let exec = makeExecutor(root: root)

        _ = await exec.execute(WebToolCall(
            name: "write_file",
            arguments: ["path": "notes.md", "content": "// header\n" + source(lines: 589, token: "line")]
        ))
        let addition = (0..<20).map { "extra \($0)" }.joined(separator: "\n")
        let edit = await exec.execute(WebToolCall(
            name: "edit_file",
            arguments: ["path": "notes.md", "old": "// header", "new": "// header\n" + addition]
        ))

        #expect(edit.hasPrefix("ok"))
    }
}
