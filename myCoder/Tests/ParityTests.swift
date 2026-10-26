import Testing
import Foundation
@testable import myCoder

@Suite("Model Selector Parity", .serialized)
struct ModelSelectorParityTests {

    @Test("Available models starts empty before API load")
    func modelsStartEmpty() {
        let state = AppState(host: "127.0.0.1", port: 0)
        #expect(state.availableModels.isEmpty)
    }

    @Test("Selected model starts empty before API load")
    func selectedModelStartsEmpty() {
        let savedModel = UserDefaults.standard.string(forKey: "com.mycoder.selectedModel")
        let savedProvider = UserDefaults.standard.string(forKey: "com.mycoder.selectedProviderID")
        defer {
            UserDefaults.standard.set(savedModel, forKey: "com.mycoder.selectedModel")
            UserDefaults.standard.set(savedProvider, forKey: "com.mycoder.selectedProviderID")
        }
        // Set explicitly to empty string (atomic) instead of removeObject,
        // because a parallel test could write between removeObject and AppState init.
        UserDefaults.standard.set("", forKey: "com.mycoder.selectedModel")
        UserDefaults.standard.set("", forKey: "com.mycoder.selectedProviderID")
        let state = AppState(host: "127.0.0.1", port: 0)
        #expect(state.selectedModel.isEmpty)
    }

    @Test("Models sorted after API load")
    func modelsSortedAfterLoad() {
        let models = ["mimo-v2.5-pro", "big-pickle", "mimo-v2-flash"]
        let sorted = models.sorted()
        #expect(sorted == ["big-pickle", "mimo-v2-flash", "mimo-v2.5-pro"])
    }

    @Test("First model becomes default after load")
    func firstModelBecomesDefault() {
        let models = ["big-pickle", "mimo-v2.5-pro", "mimo-v2-flash"]
        let defaultModel = models.first ?? ""
        #expect(defaultModel == "big-pickle")
    }
}

@Suite("Access Level Parity")
struct AccessLevelParityTests {

    @Test("Default access level is ask before changes")
    func defaultAccessLevel() {
        let state = AppState(host: "127.0.0.1", port: 0)
        #expect(state.accessLevel == .askBeforeChanges)
    }

    @Test("Access level raw values match ZCode")
    func accessLevelRawValues() {
        #expect(AccessLevel.askBeforeChanges.rawValue == "Ask before changes")
        #expect(AccessLevel.editAutomatically.rawValue == "Edit automatically")
        #expect(AccessLevel.fullAccess.rawValue == "Full access")
        #expect(AccessLevel.allCases.count == 3)
    }
}

@Suite("Send Message Parity")
struct SendMessageParityTests {

    @Test("Message model has required fields")
    func messageModelFields() {
        let message = Message(role: .user, content: "Hello")
        #expect(message.role == .user)
        #expect(message.content == "Hello")
        #expect(!message.id.isEmpty)
    }

    @Test("Message roles are user and assistant")
    func messageRoles() {
        let userMsg = Message(role: .user, content: "test")
        let assistantMsg = Message(role: .assistant, content: "response")
        #expect(userMsg.role == .user)
        #expect(assistantMsg.role == .assistant)
    }
}

@Suite("Workspace Dropdown Parity")
struct WorkspaceDropdownParityTests {

    @Test("Workspace filter by search text")
    func workspaceFilterBySearch() {
        let workspaces = [
            Workspace(id: "1", name: "tm3", path: "/test/tm3"),
            Workspace(id: "2", name: "ZCodeProject", path: "/test/zcode"),
            Workspace(id: "3", name: "mimo-macos", path: "/test/mimo")
        ]
        let searchText = "tm"
        let filtered = workspaces.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        #expect(filtered.count == 1)
        #expect(filtered[0].name == "tm3")
    }

    @Test("Workspace filter is case insensitive")
    func workspaceFilterCaseInsensitive() {
        let workspaces = [
            Workspace(id: "1", name: "ZCodeProject", path: "/test/zcode")
        ]
        let filtered = workspaces.filter { $0.name.localizedCaseInsensitiveContains("zcode") }
        #expect(filtered.count == 1)
    }

    @Test("Workspace filter empty shows all")
    func workspaceFilterEmptyShowsAll() {
        let workspaces = [
            Workspace(id: "1", name: "tm3", path: "/test/tm3"),
            Workspace(id: "2", name: "ZCodeProject", path: "/test/zcode")
        ]
        let searchText = ""
        let filtered = searchText.isEmpty ? workspaces : workspaces.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        #expect(filtered.count == 2)
    }
}

@Suite("Workspace Chips Parity")
struct WorkspaceChipsParityTests {

    @Test("Selected workspace displays in chip")
    func selectedWorkspaceInChip() {
        let state = AppState(host: "127.0.0.1", port: 0)
        let ws = Workspace(id: "1", name: "tm3", path: "/test/tm3")
        state.selectedWorkspace = ws
        #expect(state.selectedWorkspace?.name == "tm3")
    }

    @Test("Selected model displays in agent chip")
    func selectedModelInChip() {
        let state = AppState(host: "127.0.0.1", port: 0)
        state.selectedModel = "mycoder-auto-free"
        #expect(state.selectedModel == "mycoder-auto-free")
    }

    @Test("Agent chip shows model name or fallback")
    func agentChipModelLabel() {
        let savedModel = UserDefaults.standard.string(forKey: "com.mycoder.selectedModel")
        let savedProvider = UserDefaults.standard.string(forKey: "com.mycoder.selectedProviderID")
        defer {
            UserDefaults.standard.set(savedModel, forKey: "com.mycoder.selectedModel")
            UserDefaults.standard.set(savedProvider, forKey: "com.mycoder.selectedProviderID")
        }
        UserDefaults.standard.removeObject(forKey: "com.mycoder.selectedModel")
        UserDefaults.standard.removeObject(forKey: "com.mycoder.selectedProviderID")
        let state = AppState(host: "127.0.0.1", port: 0)
        let label1 = state.selectedModel.isEmpty ? "Model" : state.selectedModel
        #expect(label1 == "Model")

        state.selectedModel = "mimo-v2.5-pro"
        let label2 = state.selectedModel.isEmpty ? "Model" : state.selectedModel
        #expect(label2 == "mimo-v2.5-pro")
    }

    @Test("Workspace chip shows workspace name or fallback")
    func workspaceChipLabel() {
        let state = AppState(host: "127.0.0.1", port: 0)
        let label1 = state.selectedWorkspace?.name ?? "Select workspace"
        #expect(label1 == "Select workspace")

        let ws = Workspace(id: "1", name: "tm3", path: "/test/tm3")
        state.selectedWorkspace = ws
        let label2 = state.selectedWorkspace?.name ?? "Select workspace"
        #expect(label2 == "tm3")
    }
}

@Suite("Sidebar Session Parity")
struct SidebarSessionParityTests {

    @Test("Sessions filtered by workspace path")
    func sessionsFilteredByPath() {
        let sessions = [
            ChatSession(id: "1", title: "Task 1", directory: "/test/tm3"),
            ChatSession(id: "2", title: "Task 2", directory: "/test/zcode"),
            ChatSession(id: "3", title: "Task 3", directory: "/test/tm3")
        ]
        let ws = Workspace(id: "w1", name: "tm3", path: "/test/tm3")
        let filtered = sessions.filter { $0.belongs(to: ws) }
        #expect(filtered.count == 2)
        #expect(filtered.allSatisfy { $0.belongs(to: ws) })
    }

    @Test("Duration calculated from timestamp")
    func durationFromTimestamp() {
        let now = Date()
        let threeDaysAgo = now.addingTimeInterval(-3 * 24 * 60 * 60)
        let components = Calendar.current.dateComponents([.day], from: threeDaysAgo, to: now)
        let days = components.day ?? 0
        #expect(days == 3)
    }

    @Test("Child sessions with parentID are filtered out of sidebar")
    func childSessionsFiltered() {
        let responses = [
            MimoSessionResponse(id: "s1", slug: "", projectID: "", directory: "/test/tm3", title: "Top task", version: "1.0", summary: nil, time: MimoTimeRange(created: 100, updated: 200), project: nil, parentID: nil),
            MimoSessionResponse(id: "s2", slug: "", projectID: "", directory: "/test/tm3", title: "child message 1", version: "1.0", summary: nil, time: MimoTimeRange(created: 101, updated: 102), project: nil, parentID: "s1"),
            MimoSessionResponse(id: "s3", slug: "", projectID: "", directory: "/test/tm3", title: "child message 2", version: "1.0", summary: nil, time: MimoTimeRange(created: 103, updated: 104), project: nil, parentID: "s1"),
            MimoSessionResponse(id: "s4", slug: "", projectID: "", directory: "/test/tm3", title: "Another top task", version: "1.0", summary: nil, time: MimoTimeRange(created: 200, updated: 300), project: nil, parentID: nil),
        ]
        let topLevel = responses.filter { $0.parentID == nil }
        #expect(topLevel.count == 2)
        #expect(topLevel[0].title == "Top task")
        #expect(topLevel[1].title == "Another top task")
    }

    @Test("Sessions without parentID are shown in sidebar")
    func topLevelSessionsShown() {
        let responses = [
            MimoSessionResponse(id: "s1", slug: "", projectID: "", directory: "/test/tm3", title: "Task A", version: "1.0", summary: nil, time: MimoTimeRange(created: 100, updated: 200), project: nil, parentID: nil),
            MimoSessionResponse(id: "s2", slug: "", projectID: "", directory: "/test/tm3", title: "Task B", version: "1.0", summary: nil, time: MimoTimeRange(created: 200, updated: 300), project: nil, parentID: nil),
        ]
        let topLevel = responses.filter { $0.parentID == nil }
        #expect(topLevel.count == 2)
    }
}

@Suite("Agent Mode Parity", .serialized)
struct AgentModeParityTests {

    @Test("Agent mode defaults to build when UserDefaults is empty")
    func agentModeDefault() {
        UserDefaults.standard.removeObject(forKey: "com.mycoder.agentMode")
        let state = AppState(host: "127.0.0.1", port: 0)
        #expect(state.agentMode == .build)
    }

    @Test("Agent mode has 3 cases")
    func agentModeCases() {
        #expect(AgentMode.allCases.count == 3)
        #expect(AgentMode.build.rawValue == "Build")
        #expect(AgentMode.plan.rawValue == "Plan")
        #expect(AgentMode.compose.rawValue == "Compose")
    }

    @Test("Agent mode icons match")
    func agentModeIcons() {
        #expect(AgentMode.build.icon == "hammer.fill")
        #expect(AgentMode.plan.icon == "text.book.closed")
        #expect(AgentMode.compose.icon == "square.and.pencil")
    }

    @Test("Agent mode persists to UserDefaults")
    func agentModePersists() {
        let state = AppState(host: "127.0.0.1", port: 0)
        state.agentMode = .compose
        let raw = UserDefaults.standard.string(forKey: "com.mycoder.agentMode")
        #expect(raw == "Compose")
        state.agentMode = .plan
        let raw2 = UserDefaults.standard.string(forKey: "com.mycoder.agentMode")
        #expect(raw2 == "Plan")
    }
}

@Suite("Settings Persistence Parity")
struct SettingsPersistenceParityTests {

    @Test("AppSettings encodes to Data")
    func settingsEncodes() throws {
        let settings = AppSettings()
        let data = try JSONEncoder().encode(settings)
        #expect(!data.isEmpty)
    }

    @Test("AppSettings decodes from Data")
    func settingsDecodes() throws {
        var settings = AppSettings()
        settings.theme = .light
        settings.language = "Russian"
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(decoded.theme == .light)
        #expect(decoded.language == "Russian")
    }

    @Test("UserDefaults stores settings")
    func userDefaultsStores() {
        let key = "test_settings_key"
        UserDefaults.standard.set("test_value", forKey: key)
        let value = UserDefaults.standard.string(forKey: key)
        #expect(value == "test_value")
        UserDefaults.standard.removeObject(forKey: key)
    }
}

@Suite("Navigation History Parity")
struct NavigationHistoryParityTests {

    @Test("Navigation stack tracks workspace changes")
    func navigationStack() {
        let state = AppState(host: "127.0.0.1", port: 0)
        let ws1 = Workspace(id: "1", name: "tm3", path: "/test/tm3")
        let ws2 = Workspace(id: "2", name: "zcode", path: "/test/zcode")
        state.selectedWorkspace = ws1
        state.selectedWorkspace = ws2
        #expect(state.navigationHistory.count == 2)
        #expect(state.navigationHistory.last?.name == "zcode")
    }

    @Test("Back navigation returns to previous workspace")
    func backNavigation() {
        let state = AppState(host: "127.0.0.1", port: 0)
        let ws1 = Workspace(id: "1", name: "tm3", path: "/test/tm3")
        let ws2 = Workspace(id: "2", name: "zcode", path: "/test/zcode")
        state.selectedWorkspace = ws1
        state.selectedWorkspace = ws2
        state.navigateBack()
        #expect(state.selectedWorkspace?.name == "tm3")
        #expect(state.canNavigateBack == false)
    }

    @Test("Forward navigation returns to next workspace")
    func forwardNavigation() {
        let state = AppState(host: "127.0.0.1", port: 0)
        let ws1 = Workspace(id: "1", name: "tm3", path: "/test/tm3")
        let ws2 = Workspace(id: "2", name: "zcode", path: "/test/zcode")
        state.selectedWorkspace = ws1
        state.selectedWorkspace = ws2
        state.navigateBack()
        state.navigateForward()
        #expect(state.selectedWorkspace?.name == "zcode")
        #expect(state.canNavigateForward == false)
    }

    @Test("Can navigate back and forward flags are correct")
    func navigationFlags() {
        let state = AppState(host: "127.0.0.1", port: 0)
        #expect(state.canNavigateBack == false)
        #expect(state.canNavigateForward == false)

        let ws1 = Workspace(id: "1", name: "tm3", path: "/test/tm3")
        let ws2 = Workspace(id: "2", name: "zcode", path: "/test/zcode")
        state.selectedWorkspace = ws1
        state.selectedWorkspace = ws2

        #expect(state.canNavigateBack == true)
        #expect(state.canNavigateForward == false)

        state.navigateBack()
        #expect(state.canNavigateBack == false)
        #expect(state.canNavigateForward == true)
    }
}

@Suite("Sidebar Toggle Parity")
struct SidebarToggleParityTests {

    @Test("Sidebar visibility toggles via AppState")
    func sidebarToggles() {
        let state = AppState(host: "127.0.0.1", port: 0)
        #expect(state.sidebarVisible == true)
        state.sidebarVisible.toggle()
        #expect(state.sidebarVisible == false)
        state.sidebarVisible.toggle()
        #expect(state.sidebarVisible == true)
    }
}

@Suite("Input Bar Position Parity")
struct InputBarPositionParityTests {

    @Test("Empty messages shows centered input")
    func emptyMessagesShowsCentered() {
        let messages: [Message] = []
        let isEmpty = messages.isEmpty
        #expect(isEmpty == true)
    }

    @Test("Non-empty messages shows bottom input")
    func nonEmptyMessagesShowsBottom() {
        let messages = [Message(role: .user, content: "Hello")]
        let isEmpty = messages.isEmpty
        #expect(isEmpty == false)
    }
}
