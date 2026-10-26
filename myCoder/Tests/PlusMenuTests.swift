import Testing
import Foundation
@testable import myCoder

@Suite("Plus Button Menu")
struct PlusMenuTests {

    @Test("Plus menu has correct items")
    func plusMenuItems() {
        let items = PlusMenuItem.allCases
        #expect(items.count == 5)
        #expect(items[0] == .addAttachment)
        #expect(items[1] == .addPhoto)
        #expect(items[2] == .insertMention)
        #expect(items[3] == .insertCommand)
        #expect(items[4] == .insertSession)
    }

    @Test("Plus menu item icons match")
    func plusMenuIcons() {
        #expect(PlusMenuItem.addAttachment.icon == "paperclip")
        #expect(PlusMenuItem.addPhoto.icon == "photo")
        #expect(PlusMenuItem.insertMention.icon == "at")
        #expect(PlusMenuItem.insertCommand.icon == "slash.forward")
        #expect(PlusMenuItem.insertSession.icon == "number")
    }

    @Test("Plus menu item labels match")
    func plusMenuLabels() {
        #expect(PlusMenuItem.addAttachment.label == "Add attachment")
        #expect(PlusMenuItem.addPhoto.label == "Add photo")
        #expect(PlusMenuItem.insertMention.label == "Insert @ mention")
        #expect(PlusMenuItem.insertCommand.label == "Insert / command")
        #expect(PlusMenuItem.insertSession.label == "Insert # session")
    }

    @Test("Plus menu item prefixes for text insertion")
    func plusMenuPrefixes() {
        #expect(PlusMenuItem.insertMention.prefix == "@")
        #expect(PlusMenuItem.insertCommand.prefix == "/")
        #expect(PlusMenuItem.insertSession.prefix == "#")
    }
}

@Suite("API Response Handling")
struct APIResponseTests {

    @Test("SyncStartResponse decodes with session field")
    func syncStartResponseSession() throws {
        let json = """
        {
            "session": {
                "id": "ses_123",
                "slug": "test",
                "projectID": "proj_1",
                "directory": "/tmp",
                "title": "Fix bug",
                "version": "1.0",
                "summary": null,
                "time": {"created": 100, "updated": 200},
                "project": null,
                "parentID": null
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SyncStartResponse.self, from: json)
        #expect(response.session?.id == "ses_123")
        #expect(response.session?.title == "Fix bug")
    }

    @Test("SyncStartResponse decodes with direct session fields")
    func syncStartResponseDirect() throws {
        let json = """
        {
            "id": "ses_456",
            "slug": "direct",
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

        let response = try JSONDecoder().decode(SyncStartResponse.self, from: json)
        #expect(response.session?.id == "ses_456")
    }

    @Test("SyncStartResponse decodes simple response")
    func syncStartResponseSimple() throws {
        let json = """
        {
            "id": "ses_789",
            "title": "Simple task"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SyncStartResponse.self, from: json)
        #expect(response.session?.id == "ses_789")
        #expect(response.session?.title == "Simple task")
    }
}
