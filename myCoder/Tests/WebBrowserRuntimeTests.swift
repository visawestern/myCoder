import Testing
import Foundation
@testable import myCoder

@Suite("Dynamic web browser runtime")
struct WebBrowserRuntimeTests {
    @Test("Effort capabilities belong to the selected live model")
    func modelSpecificEffortCapabilities() {
        let config = WebProviderConfig(
            vendor: .qwen,
            selectedModel: "Qwen3.8-Max",
            discoveredModels: [
                WebProviderModel(name: "Qwen3.8-Max", availableEfforts: [.low, .high]),
                WebProviderModel(name: "Qwen3-Coder", availableEfforts: [])
            ],
            discoveredEffortLevels: [.low, .medium, .high]
        )
        #expect(WebProviderSelectionLogic.availableEfforts(for: config) == [.low, .high])

        var noThinking = config
        noThinking.selectedModel = "Qwen3-Coder"
        #expect(WebProviderSelectionLogic.availableEfforts(for: noThinking).isEmpty)
    }

    @Test("Old model records decode without availableEfforts")
    func oldModelDecodeMigration() throws {
        let data = Data(#"{"name":"legacy","availableModes":["auto"],"supportsImageGeneration":false,"supportsDeepResearch":false,"supportsWebDev":false}"#.utf8)
        let model = try JSONDecoder().decode(WebProviderModel.self, from: data)
        #expect(model.name == "legacy")
        #expect(model.availableEfforts.isEmpty)
        #expect(model.parameterProfile.isEmpty)
    }

    @Test("Named web sessions persist independently and active selection switches")
    func namedSessionsRoundTripAndActivation() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("mycoder-named-sessions-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let first = WebSessionStore(
            cookies: [BrowserCookie(name: "sid", value: "first", domain: "kimi.com", expiresEpoch: 9_999_999_999)],
            localStorage: ["account": "first"],
            savedAt: Date(timeIntervalSince1970: 100)
        )
        let second = WebSessionStore(
            cookies: [BrowserCookie(name: "sid", value: "second", domain: "kimi.com", expiresEpoch: 9_999_999_999)],
            localStorage: ["account": "second"],
            savedAt: Date(timeIntervalSince1970: 200)
        )
        try WebSessionManager.persist(first, providerId: "kimi", homeDirectory: home,
                                      sessionID: "account-first", sessionName: "Personal")
        try WebSessionManager.persist(second, providerId: "kimi", homeDirectory: home,
                                      sessionID: "account-second", sessionName: "Work")

        let listed = WebSessionManager.list(providerId: "kimi", homeDirectory: home)
        #expect(Set(listed.map(\.id)) == ["account-first", "account-second"])
        #expect(listed.first(where: { $0.id == "account-first" })?.name == "Personal")
        #expect(listed.first(where: { $0.id == "account-second" })?.name == "Work")
        #expect(WebSessionManager.restore(providerId: "kimi", homeDirectory: home,
                                          sessionID: "account-first")?.localStorage["account"] == "first")
        #expect(WebSessionManager.restore(providerId: "kimi", homeDirectory: home,
                                          sessionID: "account-second")?.localStorage["account"] == "second")

        var config = WebProviderConfig(id: "kimi", vendor: .kimi,
                                       activeSessionID: "account-first",
                                       activeSessionName: "Personal")
        config.activeSessionID = "account-second"
        config.activeSessionName = "Work"
        #expect(config.activeSessionID == "account-second")
        #expect(config.activeSessionName == "Work")
        #expect(WebSessionManager.restore(providerId: "kimi", homeDirectory: home,
                                          sessionID: config.activeSessionID ?? "")?.cookies.first?.value == "second")
    }

    @Test("Remote chat mappings isolate local chat, project and active login")
    func remoteChatMappingIsolationAndRoundTrip() {
        let suiteName = "WebRemoteChatStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstKey = WebRemoteChatKey(providerID: "qwen", activeSessionID: "work", projectID: "project-a", localChatID: "chat-1")
        let secondKey = WebRemoteChatKey(providerID: "qwen", activeSessionID: "work", projectID: "project-a", localChatID: "chat-2")
        let otherLoginKey = WebRemoteChatKey(providerID: "qwen", activeSessionID: "personal", projectID: "project-a", localChatID: "chat-1")
        let first = WebRemoteChatMapping(key: firstKey, remoteChatID: "remote-1", remoteURL: "https://chat.qwen.ai/chat/remote-1", verifiedTitle: "First")
        let second = WebRemoteChatMapping(key: secondKey, remoteChatID: "remote-2", remoteURL: "https://chat.qwen.ai/chat/remote-2", verifiedTitle: "Second")
        let otherLogin = WebRemoteChatMapping(key: otherLoginKey, remoteChatID: "remote-3", remoteURL: "https://chat.qwen.ai/chat/remote-3", verifiedTitle: "Personal")

        WebRemoteChatStore.upsert(first, defaults: defaults)
        WebRemoteChatStore.upsert(second, defaults: defaults)
        WebRemoteChatStore.upsert(otherLogin, defaults: defaults)

        #expect(WebRemoteChatStore.mapping(for: firstKey, defaults: defaults)?.remoteChatID == "remote-1")
        #expect(WebRemoteChatStore.mapping(for: secondKey, defaults: defaults)?.remoteChatID == "remote-2")
        #expect(WebRemoteChatStore.mapping(for: otherLoginKey, defaults: defaults)?.remoteChatID == "remote-3")
        WebRemoteChatStore.clear(providerID: "qwen", activeSessionID: "work", defaults: defaults)
        #expect(WebRemoteChatStore.mapping(for: firstKey, defaults: defaults) == nil)
        #expect(WebRemoteChatStore.mapping(for: otherLoginKey, defaults: defaults)?.remoteChatID == "remote-3")
    }

    @Test("Remote chat storage keys cannot collide on delimiter-containing identities")
    func remoteChatKeyDelimiterCollisionIsImpossible() {
        let left = WebRemoteChatKey(
            providerID: "qwen",
            activeSessionID: "work::project",
            projectID: "chat",
            localChatID: "local"
        )
        let right = WebRemoteChatKey(
            providerID: "qwen",
            activeSessionID: "work",
            projectID: "project::chat",
            localChatID: "local"
        )
        #expect(left.storageKey != right.storageKey)
    }

    @Test("Legacy model record migrates discovery status without rejecting valid model")
    func legacyModelStatusMigration() throws {
        let data = Data(#"{"name":"Qwen3.8-Max","availableModes":[],"availableEfforts":[],"supportsImageGeneration":false,"supportsDeepResearch":false,"supportsWebDev":false}"#.utf8)
        let model = try JSONDecoder().decode(WebProviderModel.self, from: data)
        #expect(model.name == "Qwen3.8-Max")
        #expect(model.discoveryStatus == .notDetected)
        #expect(model.isLiveDiscovered == false)
    }

    @Test("Journal records the verified remote chat ID")
    func journalKeepsRemoteChatID() throws {
        let suiteName = "WebBrowserJournalRemote.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let record = WebBrowserActionRecord(action: "send_started",
                                            projectID: "project",
                                            chatID: "local",
                                            providerID: "qwen",
                                            providerName: "Qwen",
                                            modelID: "Qwen3.8-Max",
                                            effort: .high,
                                            remoteChatID: "remote-uuid",
                                            detail: "verified")
        let loaded = WebBrowserActionJournal.append(record, defaults: defaults)
        #expect(loaded.last?.remoteChatID == "remote-uuid")
    }

    @Test("Legacy persisted UI labels are purged before catalog rendering")
    func legacyUiLabelsAreSanitized() {
        let config = WebProviderConfig(vendor: .qwen,
                                       selectedModel: "Model",
                                       discoveredModels: [
                                           WebProviderModel(name: "Model"),
                                           WebProviderModel(name: "Model Comparison"),
                                           WebProviderModel(name: "Qwen3.8-Max")
                                       ])
        let sanitized = WebProviderStore.sanitize(config)
        #expect(sanitized.discoveredModels.map(\.name) == ["Qwen3.8-Max"])
        #expect(sanitized.selectedModel == "Qwen3.8-Max")
        #expect(!sanitized.allModels.contains("Model"))
    }

    @Test("Unselectable discovered candidates stay visible but never enter sendable model list")
    func unselectableCandidatesAreFilteredFromAllModels() {
        let invalid = WebProviderModel(name: "Model Comparison",
                                       discoveryStatus: .notDetected,
                                       isLiveDiscovered: false,
                                       isSelectable: false)
        let active = WebProviderModel(name: "Qwen3-Coder",
                                      discoveryStatus: .active,
                                      isLiveDiscovered: true,
                                      isSelectable: true)
        let config = WebProviderConfig(vendor: .qwen,
                                       selectedModel: "Qwen3-Coder",
                                       discoveredModels: [invalid, active])
        #expect(config.discoveredModels.count == 2)
        #expect(config.allModels == ["Qwen3-Coder"])
        #expect(WebProviderSelectionLogic.selectingModel("Model Comparison", in: config) == config)
    }

    @Test("Browser instance identity isolates project, chat and provider")
    func instanceIdentity() {
        let first = WebBrowserInstanceKey(projectID: "project-a", chatID: "chat-1", providerID: "kimi")
        let same = WebBrowserInstanceKey(projectID: "project-a", chatID: "chat-1", providerID: "kimi")
        let differentChat = WebBrowserInstanceKey(projectID: "project-a", chatID: "chat-2", providerID: "kimi")
        let differentProject = WebBrowserInstanceKey(projectID: "project-b", chatID: "chat-1", providerID: "kimi")
        let differentLogin = WebBrowserInstanceKey(projectID: "project-a", chatID: "chat-1", providerID: "kimi", activeSessionID: "work")
        #expect(first == same)
        #expect(first != differentChat)
        #expect(first != differentProject)
        #expect(first != differentLogin)
        #expect(first.storageKey != differentChat.storageKey)
        #expect(first.storageKey != differentLogin.storageKey)
    }

    @Test("Browser action journal is bounded and keeps routing metadata")
    func boundedJournal() {
        let suiteName = "WebBrowserRuntimeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let config = WebProviderConfig(vendor: .kimi, displayName: "Kimi")
        var latest: [WebBrowserActionRecord] = []
        for index in 0..<(WebBrowserActionJournal.maxRecords + 10) {
            latest = WebBrowserActionJournal.append(
                WebBrowserActionRecord(
                    action: "send_started",
                    projectID: "project",
                    chatID: "chat-\(index)",
                    providerID: config.id,
                    providerName: config.displayName,
                    modelID: "K3",
                    effort: nil,
                    detail: "background WKWebView"
                ),
                defaults: defaults
            )
        }
        #expect(latest.count == WebBrowserActionJournal.maxRecords)
        #expect(latest.last?.chatID == "chat-\(WebBrowserActionJournal.maxRecords + 9)")
        defaults.removePersistentDomain(forName: suiteName)
    }
}
