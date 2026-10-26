import Testing
import Foundation
@testable import myCoder

@Suite("VCS diff decoding")
struct VcsDiffDecodingTests {

    @Test("Decodes OpenCode array response with file field")
    func decodesArrayResponse() throws {
        let json = """
        [
          {"file": "Sources/App.swift", "status": "modified", "additions": 12, "deletions": 3},
          {"file": "README.md", "status": "added", "additions": 5, "deletions": 0}
        ]
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(MimoVcsDiffResponse.self, from: json)
        #expect(response.files.count == 2)
        #expect(response.files[0].path == "Sources/App.swift")
        #expect(response.files[0].additions == 12)
        #expect(response.files[1].status == "added")
    }

    @Test("Decodes legacy wrapped response with path field")
    func decodesWrappedResponse() throws {
        let json = """
        {"files":[{"path":"a.swift","status":"modified","additions":1,"deletions":0}]}
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(MimoVcsDiffResponse.self, from: json)
        #expect(response.files.count == 1)
        #expect(response.files[0].path == "a.swift")
    }
}

@Suite("Git directory resolution")
struct GitDirectoryResolutionTests {

    @Test("Prefers session directory over workspace path")
    func prefersSessionDirectory() {
        let path = SessionContextLoader.gitDirectoryPath(
            workspacePath: "/Users/test/workspace",
            sessionDirectory: "/Users/test/project"
        )
        #expect(path == "/Users/test/project")
    }

    @Test("Falls back to workspace when session directory empty")
    func fallsBackToWorkspace() {
        let path = SessionContextLoader.gitDirectoryPath(
            workspacePath: "/Users/test/workspace",
            sessionDirectory: ""
        )
        #expect(path == "/Users/test/workspace")
    }

    @Test("Returns nil when both paths empty")
    func nilWhenEmpty() {
        let path = SessionContextLoader.gitDirectoryPath(
            workspacePath: nil,
            sessionDirectory: nil
        )
        #expect(path == nil)
    }
}
