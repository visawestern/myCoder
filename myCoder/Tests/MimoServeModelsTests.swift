import Testing
import Foundation
@testable import myCoder

@Suite("Mimo Serve API Models")
struct MimoServeModelsTests {

    // MARK: - Health Response

    @Test("Decode health response from JSON")
    func decodeHealthResponse() throws {
        let json = #"{"healthy":true,"version":"0.1.0"}"#
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(MimoHealthResponse.self, from: data)

        #expect(response.healthy == true)
        #expect(response.version == "0.1.0")
    }

    @Test("Decode unhealthy health response")
    func decodeUnhealthyResponse() throws {
        let json = #"{"healthy":false,"version":"0.0.1"}"#
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(MimoHealthResponse.self, from: data)

        #expect(response.healthy == false)
    }

    // MARK: - Project Response

    @Test("Decode project response from JSON")
    func decodeProjectResponse() throws {
        let json = """
        {
            "id": "global",
            "worktree": "/Users/apple/projects/mimo-macos",
            "time": {"created": 1781178496145, "updated": 1781851620535},
            "sandboxes": []
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(MimoProjectResponse.self, from: data)

        #expect(response.id == "global")
        #expect(response.worktree == "/Users/apple/projects/mimo-macos")
        #expect(response.sandboxes.isEmpty)
    }

    // MARK: - Session Response

    @Test("Decode session response from JSON")
    func decodeSessionResponse() throws {
        let json = """
        {
            "id": "ses_1234567890",
            "slug": "gentle-planet",
            "projectID": "global",
            "directory": "/Users/apple/projects/test",
            "title": "Test Session",
            "version": "0.1.0",
            "summary": {"additions": 10, "deletions": 5, "files": 3},
            "time": {"created": 1781851397123, "updated": 1781851643613},
            "project": {"id": "global", "worktree": "/"}
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(MimoSessionResponse.self, from: data)

        #expect(response.id == "ses_1234567890")
        #expect(response.slug == "gentle-planet")
        #expect(response.title == "Test Session")
        #expect(response.summary?.additions == 10)
        #expect(response.summary?.deletions == 5)
        #expect(response.summary?.files == 3)
    }

    @Test("Decode sessions array from JSON")
    func decodeSessionsArray() throws {
        let json = """
        [
            {
                "id": "ses_001",
                "slug": "session-one",
                "projectID": "global",
                "directory": "/test",
                "title": "Session 1",
                "version": "0.1.0",
                "summary": {"additions": 0, "deletions": 0, "files": 0},
                "time": {"created": 1000, "updated": 2000},
                "project": {"id": "global", "worktree": "/"}
            },
            {
                "id": "ses_002",
                "slug": "session-two",
                "projectID": "global",
                "directory": "/test",
                "title": "Session 2",
                "version": "0.1.0",
                "summary": {"additions": 5, "deletions": 2, "files": 1},
                "time": {"created": 3000, "updated": 4000},
                "project": {"id": "global", "worktree": "/"}
            }
        ]
        """
        let data = json.data(using: .utf8)!
        let sessions = try JSONDecoder().decode([MimoSessionResponse].self, from: data)

        #expect(sessions.count == 2)
        #expect(sessions[0].id == "ses_001")
        #expect(sessions[1].id == "ses_002")
    }

    // MARK: - Session Status Response

    @Test("Decode session status response")
    func decodeSessionStatusResponse() throws {
        let json = """
        {
            "id": "ses_1234567890",
            "status": "running",
            "title": "Building feature",
            "time": {"created": 1000, "updated": 2000}
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(MimoSessionStatusResponse.self, from: data)

        #expect(response.id == "ses_1234567890")
        #expect(response.status == "running")
    }

    // MARK: - Provider Response

    @Test("Decode provider response")
    func decodeProviderResponse() throws {
        let json = """
        {
            "id": "openai",
            "name": "OpenAI",
            "models": {
                "gpt-4o": {"id": "gpt-4o", "name": "GPT-4o", "status": "active"},
                "gpt-4o-mini": {"id": "gpt-4o-mini", "name": "GPT-4o Mini", "status": "active"}
            }
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(MimoProviderResponse.self, from: data)

        #expect(response.id == "openai")
        #expect(response.name == "OpenAI")
        #expect(response.models.count == 2)
    }

    @Test("Decode provider model with variants capabilities and limits")
    func decodeFullProviderModel() throws {
        let json = """
        {
            "id": "mycoder-auto-free",
            "name": "myCoder Auto Free",
            "providerID": "mimo",
            "status": "active",
            "capabilities": {"reasoning": true, "toolcall": true},
            "variants": {
                "low": {"reasoningEffort": "low"},
                "high": {"reasoningEffort": "high"}
            },
            "limit": {"context": 128000, "output": 8192},
            "cost": {"input": 0, "output": 0}
        }
        """
        let data = json.data(using: .utf8)!
        let model = try JSONDecoder().decode(MimoProviderModel.self, from: data)

        #expect(model.capabilities?.reasoning == true)
        #expect(model.variants?["high"]?.reasoningEffort == "high")
        #expect(model.limit?.context == 128000)
        #expect(model.cost?.output == 0)
    }
}
