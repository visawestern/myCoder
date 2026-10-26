import Testing
import Foundation
@testable import myCoder

@Suite("Project web tool executor — todo_read/todo_write (plan Раздел 12)")
struct ProjectWebToolTodoTests {

    private func makeRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-webtodo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeExecutor(root: URL) -> ProjectWebToolExecutor {
        ProjectWebToolExecutor(projectRoot: root.path, accessLevel: .fullAccess)
    }

    @Test("todo_write persists todos and todo_read returns them")
    func todoWriteThenRead() async throws {
        let root = try makeRoot()
        let exec = makeExecutor(root: root)

        let todos = "{\"todos\": [{\"id\": \"1\", \"content\": \"Fix bug\", \"status\": \"pending\"}, {\"id\": \"2\", \"content\": \"Write tests\", \"status\": \"completed\"}]}"
        let writeResult = await exec.execute(WebToolCall(name: "todo_write", arguments: ["todos": todos]))

        #expect(writeResult.hasPrefix("ok"), "todo_write should succeed, got: \(writeResult)")

        let readResult = await exec.execute(WebToolCall(name: "todo_read", arguments: [:]))
        #expect(readResult.contains("Fix bug"), "todo_read should contain first todo")
        #expect(readResult.contains("Write tests"), "todo_read should contain second todo")
        #expect(readResult.contains("pending"), "todo_read should show pending status")
        #expect(readResult.contains("completed"), "todo_read should show completed status")
    }

    @Test("todo_read returns empty message when no todos exist")
    func todoReadEmpty() async throws {
        let root = try makeRoot()
        let exec = makeExecutor(root: root)

        let readResult = await exec.execute(WebToolCall(name: "todo_read", arguments: [:]))
        #expect(readResult.contains("no todos") || readResult.contains("empty") || readResult == "[]",
                "todo_read should indicate no todos, got: \(readResult)")
    }

    @Test("todo_write replaces existing todos")
    func todoWriteReplaces() async throws {
        let root = try makeRoot()
        let exec = makeExecutor(root: root)

        let first = "{\"todos\": [{\"id\": \"1\", \"content\": \"First\", \"status\": \"pending\"}]}"
        _ = await exec.execute(WebToolCall(name: "todo_write", arguments: ["todos": first]))

        let second = "{\"todos\": [{\"id\": \"2\", \"content\": \"Second\", \"status\": \"in_progress\"}]}"
        _ = await exec.execute(WebToolCall(name: "todo_write", arguments: ["todos": second]))

        let readResult = await exec.execute(WebToolCall(name: "todo_read", arguments: [:]))
        #expect(readResult.contains("Second"), "should contain the new todo")
        #expect(!readResult.contains("First"), "should NOT contain the replaced todo")
    }

    @Test("todo_write with invalid JSON returns error")
    func todoWriteInvalidJSON() async throws {
        let root = try makeRoot()
        let exec = makeExecutor(root: root)

        let result = await exec.execute(WebToolCall(name: "todo_write", arguments: ["todos": "not valid json"]))
        #expect(result.contains("error") || result.contains("invalid"), "invalid JSON should error, got: \(result)")
    }

    // MARK: - P1: Wrapper format round-trip

    @Test("todo_read handles {\"todos\": [...]} wrapper written directly to disk")
    func todoReadWrapperFormat() async throws {
        let root = try makeRoot()
        let exec = makeExecutor(root: root)

        // Write wrapper-format JSON directly to disk (bypassing todoWrite normalizer)
        let wrapperJSON = """
        {"todos": [{"id": "w1", "content": "Wrapper todo", "status": "pending"}]}
        """
        let todoDir = root.appendingPathComponent(".mycoder")
        try FileManager.default.createDirectory(at: todoDir, withIntermediateDirectories: true)
        try wrapperJSON.write(to: todoDir.appendingPathComponent("todos.json"), atomically: true, encoding: .utf8)

        let readResult = await exec.execute(WebToolCall(name: "todo_read", arguments: [:]))
        #expect(readResult.contains("Wrapper todo"),
                "todo_read must handle wrapper format from disk, got: \(readResult)")
    }

    @Test("todo_write then todo_read round-trips both formats")
    func todoRoundTripBothFormats() async throws {
        let root = try makeRoot()
        let exec = makeExecutor(root: root)

        // Write via wrapper format
        let wrapper = "{\"todos\": [{\"id\": \"r1\", \"content\": \"Round trip\", \"status\": \"done\"}]}"
        let wr = await exec.execute(WebToolCall(name: "todo_write", arguments: ["todos": wrapper]))
        #expect(wr.hasPrefix("ok"), "write should succeed: \(wr)")

        // Read should return the todo
        let rd = await exec.execute(WebToolCall(name: "todo_read", arguments: [:]))
        #expect(rd.contains("Round trip"), "read after wrapper write must return todos, got: \(rd)")

        // Write via bare array format
        let bare = "[{\"id\": \"r2\", \"content\": \"Bare format\", \"status\": \"pending\"}]"
        let br = await exec.execute(WebToolCall(name: "todo_write", arguments: ["todos": bare]))
        #expect(br.hasPrefix("ok"), "bare write should succeed: \(br)")

        let brd = await exec.execute(WebToolCall(name: "todo_read", arguments: [:]))
        #expect(brd.contains("Bare format"), "read after bare write must return todos, got: \(brd)")
    }
}
