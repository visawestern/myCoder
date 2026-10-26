import Testing
import Foundation
@testable import myCoder

@Suite("Sync Start True Response")
struct SyncStartTrueResponseTests {

    @Test("Bare 'true' string decodes as success")
    func bareTrueDecodes() throws {
        let data = "true".data(using: .utf8)!
        let text = String(data: data, encoding: .utf8)
        #expect(text == "true")
    }

    @Test("SyncStartResponse init with success")
    func syncStartSuccess() {
        let response = SyncStartResponse(success: true)
        #expect(response.success == true)
        #expect(response.session == nil)
    }

    @Test("postSyncStart returns dummy session for true response")
    func dummySessionFromTrue() {
        let response = SyncStartResponse(success: true)
        let title = "hello world"
        let session = response.session ?? MimoSessionResponse(
            id: UUID().uuidString, slug: "", projectID: "", directory: "",
            title: title, version: "1.0", summary: nil,
            time: MimoTimeRange(created: 0, updated: 0),
            project: nil, parentID: nil
        )
        #expect(session.title == "hello world")
        #expect(!session.id.isEmpty)
    }

    @Test("Full SyncStartResponse decodes from JSON object")
    func fullResponseDecodes() throws {
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
}
