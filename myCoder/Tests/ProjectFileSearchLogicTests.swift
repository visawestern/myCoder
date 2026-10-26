import Foundation
import Testing
@testable import myCoder

@Suite("IDX-03 persistent project-file search")
struct ProjectFileSearchLogicTests {
    private func record(_ path: String, _ text: String) -> FileIndexRecord {
        FileIndexRecord(
            path: path,
            hash: "hash-\(path)",
            size: text.utf8.count,
            lastModified: 1,
            language: "swift",
            searchableText: text
        )
    }

    @Test("file search returns content matches ranked before path-only matches")
    func contentMatchesAreRanked() {
        let records = [
            record("Sources/Auth.swift", "func refreshAccessToken() { /* token */ }"),
            record("Docs/token-notes.md", "deployment notes"),
            record("Sources/Other.swift", "func unrelated() {}")
        ]
        let matches = ProjectFileSearchLogic.search(query: "access token", records: records)
        #expect(matches.map(\.path) == ["Sources/Auth.swift"])
    }

    @Test("file search ignores empty/whitespace queries and never returns binary records")
    func emptyAndBinaryQueriesAreSafe() {
        let binary = FileIndexRecord(
            path: "Assets/logo.bin",
            hash: "bin",
            size: 4,
            lastModified: 1,
            language: "binary",
            searchableText: nil
        )
        #expect(ProjectFileSearchLogic.search(query: "   ", records: [binary]).isEmpty)
        #expect(ProjectFileSearchLogic.search(query: "logo", records: [binary]).isEmpty)
    }
}
