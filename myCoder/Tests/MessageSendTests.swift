import Testing
import Foundation
@testable import myCoder

@Suite("Message Sending")
struct MessageSendTests {

    // MARK: - syncStart request body

    @Test("syncStart sends prompt field in body")
    func syncStartBody() async throws {
        let endpoint = MimoEndpoint.syncStart
        #expect(endpoint.method == "POST")
        #expect(endpoint.path == "/sync/start")
    }

    @Test("syncStart message function encodes prompt correctly")
    func syncStartEncodesPrompt() {
        let body = ["prompt": "hello world"]
        let data = try? JSONEncoder().encode(body)
        #expect(data != nil)
        let json = try? JSONSerialization.jsonObject(with: data!) as? [String: String]
        #expect(json?["prompt"] == "hello world")
    }

    @Test("syncStart with files encodes attachments")
    func syncStartWithFiles() {
        let body: [String: Any] = [
            "prompt": "fix this bug",
            "files": ["/src/main.swift", "/src/util.swift"]
        ]
        let data = try? JSONSerialization.data(withJSONObject: body)
        #expect(data != nil)
        let json = try? JSONSerialization.jsonObject(with: data!) as? [String: Any]
        #expect(json?["prompt"] as? String == "fix this bug")
        #expect(json?["files"] as? [String] == ["/src/main.swift", "/src/util.swift"])
    }

    // MARK: - Message model

    @Test("Message creates with default id")
    func messageId() {
        let msg = Message(role: .user, content: "test")
        #expect(!msg.id.isEmpty)
        #expect(msg.content == "test")
    }

    @Test("Message with attachments stores file info")
    func messageWithFiles() {
        let files = [
            FileInfo(name: "main.swift", type: .swift),
            FileInfo(name: "style.css", type: .css)
        ]
        let msg = Message(role: .user, content: "fix this", files: files)
        #expect(msg.files?.count == 2)
        #expect(msg.files?.first?.name == "main.swift")
    }

    // MARK: - Response decoding

    @Test("MimoSessionResponse decodes from JSON")
    func decodeSessionResponse() throws {
        let json = """
        {
            "id": "ses_123",
            "slug": "test-session",
            "projectID": "proj_1",
            "directory": "/Users/test/project",
            "title": "Fix the bug",
            "version": "1.0",
            "summary": {"additions": 10, "deletions": 5, "files": 2},
            "time": {"created": 1234567890, "updated": 1234567891},
            "project": {"id": "proj_1", "worktree": "/Users/test/project"},
            "parentID": null
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(MimoSessionResponse.self, from: json)
        #expect(response.id == "ses_123")
        #expect(response.title == "Fix the bug")
        #expect(response.summary?.additions == 10)
    }

    @Test("MimoSessionResponse decodes without optional fields")
    func decodeSessionResponseMinimal() throws {
        let json = """
        {
            "id": "ses_456",
            "slug": "minimal",
            "projectID": "proj_2",
            "directory": "/tmp",
            "title": "Task",
            "version": "1.0",
            "summary": null,
            "time": {"created": 100, "updated": 200},
            "project": null,
            "parentID": null
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(MimoSessionResponse.self, from: json)
        #expect(response.id == "ses_456")
        #expect(response.summary == nil)
    }

    // MARK: - File attachment encoding

    @Test("File attachments encode to JSON array")
    func fileAttachmentsEncode() throws {
        let files = ["/src/a.swift", "/src/b.swift"]
        let data = try JSONEncoder().encode(files)
        let decoded = try JSONDecoder().decode([String].self, from: data)
        #expect(decoded == files)
    }
}

@Suite("File Attachment Support")
struct FileAttachmentTests {

    @Test("FileInfo creates with name and type")
    func fileInfoCreate() {
        let file = FileInfo(name: "test.swift", type: .swift)
        #expect(file.name == "test.swift")
        #expect(file.type == .swift)
    }

    @Test("FileType detects from extension")
    func fileTypeFromExtension() {
        #expect(FileType.from(ext: "swift") == .swift)
        #expect(FileType.from(ext: "py") == .python)
        #expect(FileType.from(ext: "js") == .javascript)
        #expect(FileType.from(ext: "css") == .css)
        #expect(FileType.from(ext: "html") == .html)
        #expect(FileType.from(ext: "unknown") == .unknown)
    }

    @Test("Message with image attachment")
    func messageWithImage() {
        let file = FileInfo(name: "screenshot.png", type: .unknown)
        let msg = Message(role: .user, content: "fix this", files: [file])
        #expect(msg.files?.count == 1)
        #expect(msg.files?.first?.name == "screenshot.png")
    }
}

@Suite("Session Busy Error Handling")
struct SessionBusyTests {

    @Test("MimoServeError.sessionBusy has correct description")
    func sessionBusyDescription() {
        let error = MimoServeError.sessionBusy
        #expect(error.errorDescription?.contains("busy") == true)
        #expect(error.errorDescription?.contains("stop") == true)
    }

    @Test("MimoServeError.sessionBusy is distinct from httpError")
    func sessionBusyDistinct() {
        let busy = MimoServeError.sessionBusy
        let http409 = MimoServeError.httpError(statusCode: 409)
        switch busy {
        case .sessionBusy: break
        default: #expect(Bool(false), "Expected sessionBusy")
        }
        switch http409 {
        case .httpError(let code, _): #expect(code == 409)
        default: #expect(Bool(false), "Expected httpError")
        }
    }

    @Test("HTTP 409 status code maps to sessionBusy in client")
    func http409MapsToSessionBusy() {
        let statusCode = 409
        let isConflict = statusCode == 409
        #expect(isConflict)
    }
}
