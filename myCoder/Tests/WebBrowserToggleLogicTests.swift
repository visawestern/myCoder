import Testing
import Foundation
@testable import myCoder

/// The top-bar Browser button must be a real toggle: hide a visible panel and
/// re-open the last web provider's browser after it was hidden. This logic is
/// pure so every selection rule is testable without AppState or a webview.
@Suite("Browser panel toggle — hide/show from the top bar")
struct WebBrowserToggleLogicTests {

    private func provider(
        _ id: String,
        name: String? = nil,
        connected: Bool = true
    ) -> WebProviderConfig {
        WebProviderConfig(
            id: id,
            vendor: .custom,
            displayName: name ?? id,
            loginConfirmedAt: connected ? Date(timeIntervalSince1970: 1) : nil
        )
    }

    private func panel(_ providerID: String) -> WebBrowserPanelConfig {
        WebBrowserPanelConfig(
            providerID: providerID,
            providerName: providerID,
            projectID: "p1",
            chatID: "c1"
        )
    }

    @Test("A visible panel hides on click")
    func visiblePanelHides() {
        let action = WebBrowserToggleLogic.action(
            panelConfig: panel("kimi"),
            selectedProviderOptionID: "web:kimi",
            activeProviderID: "kimi",
            configs: [provider("kimi")],
            projectID: "p1",
            chatID: "c1"
        )
        #expect(action == .hide)
    }

    @Test("The selected web provider re-opens a hidden panel")
    func selectedProviderOpens() {
        let action = WebBrowserToggleLogic.action(
            panelConfig: nil,
            selectedProviderOptionID: "web:qwen",
            activeProviderID: nil,
            configs: [provider("kimi"), provider("qwen", name: "Qwen")],
            projectID: "project-7",
            chatID: "chat-9"
        )
        #expect(action == .show(WebBrowserPanelConfig(
            providerID: "qwen",
            providerName: "Qwen",
            projectID: "project-7",
            chatID: "chat-9"
        )))
    }

    @Test("After hiding, the last web provider re-opens even if another provider is selected")
    func lastWebProviderWins() {
        let action = WebBrowserToggleLogic.action(
            panelConfig: nil,
            selectedProviderOptionID: "openai",
            activeProviderID: "kimi",
            configs: [provider("kimi"), provider("qwen")],
            projectID: "p1",
            chatID: "c1"
        )
        #expect(action == .show(WebBrowserPanelConfig(
            providerID: "kimi",
            providerName: "kimi",
            projectID: "p1",
            chatID: "c1"
        )))
    }

    @Test("A single web provider is the fallback when nothing was selected")
    func singleProviderFallback() {
        let action = WebBrowserToggleLogic.action(
            panelConfig: nil,
            selectedProviderOptionID: "",
            activeProviderID: nil,
            configs: [provider("chatgpt")],
            projectID: "p1",
            chatID: "c1"
        )
        #expect(action == .show(WebBrowserPanelConfig(
            providerID: "chatgpt",
            providerName: "chatgpt",
            projectID: "p1",
            chatID: "c1"
        )))
    }

    @Test("With several providers and no memory, a connected one is preferred")
    func connectedProviderPreferred() {
        let action = WebBrowserToggleLogic.action(
            panelConfig: nil,
            selectedProviderOptionID: "",
            activeProviderID: nil,
            configs: [provider("offline", connected: false), provider("online", connected: true)],
            projectID: "p1",
            chatID: "c1"
        )
        #expect(action == .show(WebBrowserPanelConfig(
            providerID: "online",
            providerName: "online",
            projectID: "p1",
            chatID: "c1"
        )))
    }

    @Test("A deleted selected provider falls back instead of dead-ending")
    func deletedSelectionFallsBack() {
        let action = WebBrowserToggleLogic.action(
            panelConfig: nil,
            selectedProviderOptionID: "web:deleted",
            activeProviderID: "deleted",
            configs: [provider("kimi")],
            projectID: "p1",
            chatID: "c1"
        )
        #expect(action == .show(WebBrowserPanelConfig(
            providerID: "kimi",
            providerName: "kimi",
            projectID: "p1",
            chatID: "c1"
        )))
    }

    @Test("No web provider means no button at all")
    func noProvidersNoButton() {
        #expect(WebBrowserToggleLogic.action(
            panelConfig: nil,
            selectedProviderOptionID: "openai",
            activeProviderID: nil,
            configs: [],
            projectID: "p1",
            chatID: "c1"
        ) == nil)
    }

    @Test("A visible panel keeps the button available even without configs")
    func visiblePanelAlwaysAvailable() {
        #expect(WebBrowserToggleLogic.action(
            panelConfig: panel("deleted"),
            selectedProviderOptionID: "",
            activeProviderID: nil,
            configs: [],
            projectID: "p1",
            chatID: "c1"
        ) == .hide)
    }
}
