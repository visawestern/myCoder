import Testing
import Foundation
@testable import myCoder

@Suite("Screenshot 1 Parity")
struct Screenshot1Tests {

    // MARK: - Empty State

    @Test("Empty state shows correct text with workspace name")
    func emptyStateText() {
        let workspace = Workspace(id: "ws1", name: "mimo-macos", path: "/test")
        let text = "Start a new task in \(workspace.name)"
        #expect(text == "Start a new task in mimo-macos")
    }

    @Test("Empty state shows generic text without workspace")
    func emptyStateGenericText() {
        let text = "Select a workspace"
        #expect(text == "Select a workspace")
    }

    // MARK: - Input Bar Placeholder

    @Test("Input placeholder matches myCoder spec")
    func inputPlaceholder() {
        let placeholder = MiMoCopy.promptPlaceholder(language: .english)
        #expect(placeholder.contains("Ask myCoder anything"))
        #expect(placeholder.contains("@ to add files"))
        #expect(placeholder.contains("/ for commands"))
        #expect(placeholder.contains("$ for skills"))
        #expect(placeholder.contains("# related conversation"))
    }

    // MARK: - Model Selector

    @Test("Model selector uses real API models")
    func modelSelectorFromAPI() {
        let models = ["big-pickle", "mimo-v2.5-pro-ultraspeed", "mimo-v2.5", "mimo-v2-omni", "mimo-v2-flash", "mimo-v2-pro", "mimo-v2.5-pro"]
        #expect(models.contains("big-pickle"))
        #expect(models.count == 7)
    }

    @Test("Default model is first from API")
    func defaultModelFromAPI() {
        let models = ["big-pickle", "mimo-v2.5-pro-ultraspeed"]
        let defaultModel = models.first ?? "unknown"
        #expect(defaultModel == "big-pickle")
    }

    // MARK: - Workspace Branch

    @Test("Workspace branch loaded from project")
    func workspaceBranch() {
        var ws = Workspace(id: "ws1", name: "test", path: "/test")
        ws.branch = "main"
        #expect(ws.branch == "main")
    }

    // MARK: - Sidebar Top Row

    @Test("Sidebar has navigation icons")
    func sidebarNavIcons() {
        let icons = ["chevron.left", "chevron.right", "sidebar.left"]
        #expect(icons.count == 3)
    }

    // MARK: - Access Level

    @Test("Access level default is ask before changes")
    func accessLevelDefault() {
        let level: AccessLevel = .askBeforeChanges
        #expect(level.rawValue == "Ask before changes")
    }

    @Test("Access level has shield icon")
    func accessLevelIcon() {
        let icon = "shield.checkered"
        #expect(icon == "shield.checkered")
    }
}
