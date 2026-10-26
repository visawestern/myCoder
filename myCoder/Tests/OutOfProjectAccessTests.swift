import Testing
import Foundation
@testable import myCoder

/// A tool call that points outside the project folder must not dead-end: the
/// user is asked for access, and an approved grant lets the call run.
@Suite("Out-of-project access")
struct OutOfProjectAccessTests {

    private func makeTempDir(_ name: String = UUID().uuidString) throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mycoder-access-\(name)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    @Test("The grant root is the requested folder itself")
    func grantRootOfDirectory() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        #expect(OutOfProjectAccessLogic.grantRoot(forPath: dir) == (dir as NSString).standardizingPath)
    }

    @Test("The grant root of a file is its parent folder")
    func grantRootOfFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let file = (dir as NSString).appendingPathComponent("notes.md")
        #expect(OutOfProjectAccessLogic.grantRoot(forPath: file) == (dir as NSString).standardizingPath)
    }

    @Test("A path outside the project is not accessible without a grant")
    func outsidePathNeedsGrant() {
        let accessible = OutOfProjectAccessLogic.isAccessible(
            path: "/Users/apple/projects/other/file.txt",
            projectRoot: "/Users/apple/projects/demo"
        )
        #expect(accessible == false)
    }

    @Test("A granted folder makes the path accessible")
    func grantedFolderIsAccessible() {
        let accessible = OutOfProjectAccessLogic.isAccessible(
            path: "/Users/apple/projects/other/file.txt",
            projectRoot: "/Users/apple/projects/demo",
            grantedRoots: ["/Users/apple/projects/other"]
        )
        #expect(accessible == true)
    }

    @Test("Validation rejects an outside path without a grant")
    func validationRejectsOutsidePath() {
        let call = WebToolCall(name: "read_file", arguments: ["path": "/Users/apple/projects/other/file.txt"])
        let error = WebToolProtocolEmulator.validate(
            call,
            projectRoot: "/Users/apple/projects/demo"
        )
        #expect(error == .pathEscapesProject("/Users/apple/projects/other/file.txt"))
    }

    @Test("Validation accepts an outside path the user granted")
    func validationAcceptsGrantedPath() {
        let call = WebToolCall(name: "read_file", arguments: ["path": "/Users/apple/projects/other/file.txt"])
        let error = WebToolProtocolEmulator.validate(
            call,
            projectRoot: "/Users/apple/projects/demo",
            grantedRoots: ["/Users/apple/projects/other"]
        )
        #expect(error == nil)
    }

    @Test("The executor reads an absolute path outside the project root")
    func executorReadsAbsolutePath() async throws {
        let outside = try makeTempDir("outside")
        defer { try? FileManager.default.removeItem(atPath: outside) }
        let file = (outside as NSString).appendingPathComponent("note.txt")
        try "hello from outside".write(toFile: file, atomically: true, encoding: .utf8)

        let project = try makeTempDir("project")
        defer { try? FileManager.default.removeItem(atPath: project) }

        let executor = ProjectWebToolExecutor(projectRoot: project)
        let result = await executor.execute(
            WebToolCall(name: "read_file", arguments: ["path": file]),
            userApproved: true
        )
        #expect(result.contains("hello from outside"))
    }

    @Test("The executor lists an absolute directory outside the project root")
    func executorListsAbsoluteDirectory() async throws {
        let outside = try makeTempDir("outside-dir")
        defer { try? FileManager.default.removeItem(atPath: outside) }
        try "x".write(toFile: (outside as NSString).appendingPathComponent("a.txt"),
                     atomically: true, encoding: .utf8)

        let project = try makeTempDir("project2")
        defer { try? FileManager.default.removeItem(atPath: project) }

        let executor = ProjectWebToolExecutor(projectRoot: project)
        let result = await executor.execute(
            WebToolCall(name: "list_dir", arguments: ["path": outside]),
            userApproved: true
        )
        #expect(result.contains("a.txt"))
    }

    @Test("The approval message names the tool, the path and the project")
    func approvalMessageContent() {
        let message = OutOfProjectAccessLogic.approvalMessage(
            tool: "read_file",
            path: "/Users/apple/projects/other/file.txt",
            projectRoot: "/Users/apple/projects/demo"
        )
        #expect(message.contains("read_file"))
        #expect(message.contains("/Users/apple/projects/other/file.txt"))
        #expect(message.contains("/Users/apple/projects/demo"))
    }

    @Test("The denial message tells the model to stop retrying")
    func denialMessageContent() {
        let message = OutOfProjectAccessLogic.denialMessage(
            tool: "read_file",
            path: "/Users/apple/projects/other/file.txt"
        )
        #expect(message.contains("denied"))
        #expect(message.contains("Do not retry"))
    }
}
