import Testing
import Foundation
@testable import myCoder

@Suite("AppState MimoServe Integration")
struct AppStateIntegrationTests {

    // MARK: - MimoSession to ChatSession Mapping

    @Test("Map MimoSessionResponse to ChatSession")
    func mapSessionToChatSession() throws {
        let mimoSession = MimoSessionResponse(
            id: "ses_123",
            slug: "test-session",
            projectID: "global",
            directory: "/Users/test/project",
            title: "Test Session",
            version: "0.1.0",
            summary: MimoSessionSummary(additions: 10, deletions: 5, files: 3),
            time: MimoTimeRange(created: 1000, updated: 2000),
            project: MimoProjectRef(id: "global", worktree: "/"),
            parentID: nil
        )

        let chatSession = mimoSession.toChatSession()

        #expect(chatSession.id == "ses_123")
        #expect(chatSession.title == "Test Session")
    }

    // MARK: - MimoSessionResponse to Project Mapping

    @Test("Map MimoSessionResponse directory to Project")
    func mapSessionToProject() throws {
        let mimoSession = MimoSessionResponse(
            id: "ses_123",
            slug: "test-session",
            projectID: "global",
            directory: "/Users/test/my-project",
            title: "Test Session",
            version: "0.1.0",
            summary: MimoSessionSummary(additions: 0, deletions: 0, files: 0),
            time: MimoTimeRange(created: 1000, updated: 2000),
            project: MimoProjectRef(id: "global", worktree: "/"),
            parentID: nil
        )

        let project = mimoSession.toProject()

        #expect(project.id == "ses_123")
        #expect(project.name == "my-project")
        #expect(project.path == "/Users/test/my-project")
    }

    // MARK: - Health Check

    @Test("HealthResponse represents healthy state")
    func healthState() throws {
        let healthy = MimoHealthResponse(healthy: true, version: "0.1.0")
        let unhealthy = MimoHealthResponse(healthy: false, version: "0.0.1")

        #expect(healthy.healthy)
        #expect(!unhealthy.healthy)
    }

    // MARK: - Session Summary Computed

    @Test("SessionSummary computed properties")
    func summaryComputed() throws {
        let summary = MimoSessionSummary(additions: 100, deletions: 30, files: 15)
        let net = summary.additions - summary.deletions

        #expect(net == 70)
        #expect(summary.files == 15)
    }

    // MARK: - Model Mapping

    @Test("Provider to model list")
    func providerModels() throws {
        let provider = MimoProviderResponse(
            id: "openai",
            name: "OpenAI",
            models: [
                "gpt-4o": MimoProviderModel(id: "gpt-4o", name: "GPT-4o", status: "active"),
                "gpt-4o-mini": MimoProviderModel(id: "gpt-4o-mini", name: "GPT-4o Mini", status: "active")
            ]
        )

        #expect(provider.models["gpt-4o"] != nil)
        #expect(provider.models.count == 2)
    }
}
