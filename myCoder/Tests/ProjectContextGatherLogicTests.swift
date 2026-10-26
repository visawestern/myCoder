import Foundation
import Testing
@testable import myCoder

@Suite("A/B: project auto-search before answer")
struct ProjectContextGatherLogicTests {
    private func record(_ path: String, _ text: String?, language: String = "swift") -> FileIndexRecord {
        FileIndexRecord(
            path: path,
            hash: "hash-\(path)",
            size: text?.utf8.count ?? 0,
            lastModified: 1,
            language: language,
            searchableText: text
        )
    }

    @Test("empty query and empty records yield an empty bundle")
    func emptyInputsAreSafe() {
        let records = [record("A.swift", "func foo() {}")]
        #expect(ProjectContextGatherLogic.gather(query: "   ", records: records).isEmpty)
        #expect(ProjectContextGatherLogic.gather(query: "foo", records: []).isEmpty)
        #expect(ProjectContextGatherLogic.block(query: "", records: records) == "")
    }

    @Test("content match outranks path-only match")
    func contentOutranksPath() {
        let records = [
            record("Sources/Auth.swift", "func refreshAccessToken() { /* token */ }"),
            record("Docs/token-notes.md", "deployment notes"),
        ]
        let bundle = ProjectContextGatherLogic.gather(query: "access token", records: records)
        #expect(bundle.paths == ["Sources/Auth.swift"])
        #expect(bundle.snippet.contains("### Sources/Auth.swift"))
        #expect(bundle.snippet.contains("refreshAccessToken"))
    }

    @Test("binary records are never included")
    func binaryExcluded() {
        let records = [
            FileIndexRecord(path: "Assets/logo.bin", hash: "b", size: 4, lastModified: 1, language: "binary", searchableText: nil),
            record("Sources/A.swift", "unrelated content here"),
        ]
        #expect(ProjectContextGatherLogic.gather(query: "logo", records: records).isEmpty)
    }

    @Test("maxFiles caps the bundle deterministically")
    func maxFilesTruncates() {
        let records = (1...8).map { record("Sources/F\($0).swift", "shared token alpha") }
        let bundle = ProjectContextGatherLogic.gather(query: "shared token", records: records, maxFiles: 3)
        #expect(bundle.paths.count == 3)
        #expect(bundle.paths == ["Sources/F1.swift", "Sources/F2.swift", "Sources/F3.swift"])
    }

    @Test("maxChars caps the snippet")
    func maxCharsTruncates() {
        let big = String(repeating: "token filler line content ", count: 40)
        let records = [record("Sources/Big.swift", big)]
        let bundle = ProjectContextGatherLogic.gather(query: "token", records: records, maxChars: 200)
        #expect(bundle.snippet.count <= 200)
    }

    @Test("block wraps the snippet in project-context tags")
    func blockFormat() {
        let records = [record("Sources/Auth.swift", "func refreshAccessToken() {}")]
        let block = ProjectContextGatherLogic.block(query: "access token", records: records)
        #expect(block.hasPrefix("<project-context>\n"))
        #expect(block.hasSuffix("\n</project-context>"))
        #expect(block.contains("Sources/Auth.swift"))
    }
}
