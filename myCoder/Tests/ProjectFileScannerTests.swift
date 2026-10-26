import Testing
import Foundation
@testable import myCoder

@Suite("Project file scanner (plan Раздел 7 Блок 3)")
struct ProjectFileScannerTests {

    private func makeProject() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-scan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func write(_ root: URL, _ rel: String, _ contents: String) throws {
        let url = root.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func scanFindsFilesAndExcludesJunk() throws {
        let root = try makeProject()
        try write(root, "src/main.swift", "print(1)")
        try write(root, "README.md", "# hi")
        try write(root, ".git/config", "junk")
        try write(root, "node_modules/x/index.js", "junk")

        let records = ProjectFileScanner.scan(root: root.path)
        let paths = Set(records.map { $0.path })
        #expect(paths.contains("src/main.swift"))
        #expect(paths.contains("README.md"))
        #expect(!paths.contains(where: { $0.contains(".git") }))
        #expect(!paths.contains(where: { $0.contains("node_modules") }))
    }

    @Test func recordsHaveHashSizeLanguage() throws {
        let root = try makeProject()
        try write(root, "a.swift", "let x = 1")
        let rec = ProjectFileScanner.scan(root: root.path).first { $0.path == "a.swift" }
        let record = try #require(rec)
        #expect(record.language == "swift")
        #expect(record.size > 0)
        // Bind to a plain non-optional String: the #expect macro mis-expands
        // `!(rec?.hash ?? "").isEmpty` into an unused Bool? and never evaluates
        // the negation, so this test used to fail on a perfectly valid hash.
        let hash = record.hash
        #expect(hash.isEmpty == false)
    }

    @Test func hashChangesWithContent() {
        let h1 = ProjectFileScanner.hash(of: Data("abc".utf8))
        let h2 = ProjectFileScanner.hash(of: Data("abd".utf8))
        let h1again = ProjectFileScanner.hash(of: Data("abc".utf8))
        #expect(h1 != h2)
        #expect(h1 == h1again)   // deterministic
    }

    @Test func incrementalUpdateDetectsChange() throws {
        let root = try makeProject()
        try write(root, "a.txt", "one")
        let first = ProjectFileScanner.scan(root: root.path)
        // Modify the file → incremental delta must contain it.
        try write(root, "a.txt", "two")
        let delta = ProjectFileScanner.incrementalUpdate(root: root.path, current: first)
        #expect(delta.toUpsert.contains { $0.path == "a.txt" })
    }

    @Test func incrementalUpdateDetectsRemoval() throws {
        let root = try makeProject()
        try write(root, "keep.txt", "k")
        try write(root, "gone.txt", "g")
        let first = ProjectFileScanner.scan(root: root.path)
        try FileManager.default.removeItem(at: root.appendingPathComponent("gone.txt"))
        let delta = ProjectFileScanner.incrementalUpdate(root: root.path, current: first)
        #expect(delta.toRemove.contains("gone.txt"))
    }

    @Test func gitignorePatternExcludes() throws {
        let root = try makeProject()
        try write(root, "app.log", "x")
        try write(root, "app.swift", "y")
        let records = ProjectFileScanner.scan(root: root.path, gitignorePatterns: ["*.log"])
        let paths = Set(records.map { $0.path })
        #expect(!paths.contains("app.log"))
        #expect(paths.contains("app.swift"))
    }
}
