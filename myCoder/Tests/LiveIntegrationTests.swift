import Testing
import Foundation
@testable import myCoder

@Suite("MimoServeClient Live Integration", .enabled(if: ProcessInfo.processInfo.environment["MIMO_LIVE_TESTS"] == "1"))
struct LiveIntegrationTests {

    let client = MimoServeClient(host: "127.0.0.1", port: 8080)

    @Test("Health endpoint returns valid response")
    func healthLive() async throws {
        let health = try await client.health()
        #expect(health.healthy)
        #expect(!health.version.isEmpty)
    }

    @Test("Project current returns valid project")
    func projectCurrentLive() async throws {
        let project = try await client.projectCurrent()
        #expect(!project.id.isEmpty)
        #expect(!project.worktree.isEmpty)
    }

    @Test("Sessions endpoint returns array")
    func sessionsLive() async throws {
        let sessions = try await client.sessions()
        #expect(sessions.count >= 0)
        for session in sessions {
            #expect(!session.id.isEmpty)
        }
    }

    @Test("Providers endpoint returns providers")
    func providersLive() async throws {
        let providers = try await client.providers()
        #expect(providers.count >= 0)
        for provider in providers {
            #expect(!provider.id.isEmpty)
        }
    }

    @Test("Global config returns config")
    func configLive() async throws {
        let config = try await client.globalConfig()
        #expect(config.model != nil || config.providers != nil || config.theme != nil || config.permission != nil)
    }
}
