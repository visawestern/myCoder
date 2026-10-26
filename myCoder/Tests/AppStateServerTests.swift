import Testing
import Foundation
@testable import myCoder

@Suite("AppState Server Integration")
struct AppStateServerTests {

    // MARK: - AppState Properties

    @Test("AppState initializes with empty state")
    func emptyState() {
        let state = AppState()
        #expect(state.projects.isEmpty)
        #expect(state.serverConnected == false)
    }

    @Test("AppState has mimo client")
    func hasClient() {
        let state = AppState()
        #expect(state.serverHost == "127.0.0.1")
        #expect(state.serverPort == 4096)
    }

    @Test("AppState default server address")
    func defaultServerAddress() {
        let state = AppState()
        #expect(state.serverHost == "127.0.0.1")
        #expect(state.serverPort == 4096)
    }

    // MARK: - Server Connection State

    @Test("ServerConnected transitions correctly")
    func connectionState() {
        let state = AppState()

        state.serverConnected = true
        #expect(state.serverConnected)

        state.serverConnected = false
        #expect(!state.serverConnected)
    }

    // MARK: - Projects from Server

    @Test("AppState can hold server projects")
    func serverProjects() {
        let state = AppState()
        let project = Project(id: "test", name: "Test", path: "/test")
        state.projects = [project]
        #expect(state.projects.count == 1)
        #expect(state.projects[0].id == "test")
    }

    @Test("AppState can hold sessions")
    func serverSessions() {
        let state = AppState()
        let session = ChatSession(id: "ses_1", title: "Test Session")
        state.sessions = [session]
        #expect(state.sessions.count == 1)
        #expect(state.sessions[0].id == "ses_1")
    }

    // MARK: - Model List

    @Test("Available models list merges server and custom")
    func modelList() {
        let state = AppState()
        state.serverProviders = [
            MimoProviderResponse(
                id: "mimo",
                name: "MiMo",
                models: [
                    "GLM-5.2": MimoProviderModel(id: "GLM-5.2"),
                    "GLM-5": MimoProviderModel(id: "GLM-5")
                ]
            )
        ]
        state.customProviders = [
            CustomProvider(name: "Custom", type: .openAI, baseURL: "https://example.com", models: ["GPT-4o"])
        ]
        #expect(state.availableModels.count == 3)
        #expect(state.availableModels.contains("GLM-5.2"))
        #expect(state.availableModels.contains("GPT-4o"))
    }

    // MARK: - New MiMo Features

    @Test("AppState has workspaces")
    func hasWorkspaces() {
        let state = AppState()
        #expect(state.workspaces.isEmpty)
    }

    @Test("AppState has settings")
    func hasSettings() {
        let state = AppState()
        #expect(state.settings.theme == .dark)
        #expect(state.accessLevel == .askBeforeChanges)
        #expect(state.selectedVariant == "high")
    }

    @Test("AppState settings tab")
    func settingsTab() {
        let state = AppState()
        state.settingsTab = .modelSettings
        #expect(state.settingsTab == .modelSettings)
    }
}
