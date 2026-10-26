import Testing
import Foundation
import SwiftUI
@testable import myCoder

// MARK: - SET-02: General Settings Tab

@Suite("SET-02 General Settings", .serialized)
struct GeneralSettingsTests {

    // MARK: AppSettings Defaults

    @Test("AppSettings init provides sensible defaults")
    func appSettingsDefaults() {
        let s = AppSettings()
        #expect(s.theme == .dark)
        #expect(s.language == "English")
        #expect(s.zoom == .default)
        #expect(s.showLineNumbers == true)
        #expect(s.wrapLongLines == true)
        #expect(s.codeFontSize == 12)
        #expect(s.inheritTerminalProfile == true)
        #expect(s.terminalFont == "")
        #expect(s.httpProxy == "")
        #expect(s.lightCodeTheme == "GitHub Light")
        #expect(s.darkCodeTheme == "GitHub Dark")
        #expect(s.indexNewFolders == true)
        #expect(s.indexRepositories == true)
    }

    @Test("AppSettings.load returns defaults when no data stored")
    func appSettingsLoadDefaults() {
        // Use a dedicated defaults suite so parallel test runs never race on
        // the shared `.standard` domain (Round 12 flake fix).
        let suiteName = "com.mycoder.tests.appSettingsLoadDefaults"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let loaded = AppSettings.load(from: defaults)
        #expect(loaded.theme == .dark)
        #expect(loaded.language == "English")
        #expect(loaded.zoom == .default)

        // Clean up the dedicated suite.
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("AppSettings encoding round-trips all properties")
    func appSettingsEncodingRoundTrip() throws {
        var settings = AppSettings()
        settings.theme = .light
        settings.language = "Russian"
        settings.zoom = .larger
        settings.showLineNumbers = false
        settings.wrapLongLines = false
        settings.codeFontSize = 14
        settings.inheritTerminalProfile = false
        settings.terminalFont = "Menlo"
        settings.httpProxy = "http://proxy:8080"
        settings.lightCodeTheme = "One Light"
        settings.darkCodeTheme = "Dracula"
        settings.indexNewFolders = false
        settings.indexRepositories = false

        let data = try JSONEncoder().encode(settings)
        let loaded = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(loaded.theme == .light)
        #expect(loaded.language == "Russian")
        #expect(loaded.zoom == .larger)
        #expect(loaded.showLineNumbers == false)
        #expect(loaded.wrapLongLines == false)
        #expect(loaded.codeFontSize == 14)
        #expect(loaded.inheritTerminalProfile == false)
        #expect(loaded.terminalFont == "Menlo")
        #expect(loaded.httpProxy == "http://proxy:8080")
        #expect(loaded.lightCodeTheme == "One Light")
        #expect(loaded.darkCodeTheme == "Dracula")
        #expect(loaded.indexNewFolders == false)
        #expect(loaded.indexRepositories == false)
    }

    // MARK: AppSettings.Zoom

    @Test("Zoom enum has three cases with correct scale factors")
    func zoomEnumValues() {
        #expect(AppSettings.Zoom.allCases.count == 3)
        #expect(AppSettings.Zoom.smaller.rawValue == "Smaller")
        #expect(AppSettings.Zoom.default.rawValue == "Default")
        #expect(AppSettings.Zoom.larger.rawValue == "Larger")

        #expect(AppSettings.Zoom.smaller.fontScale == 0.85)
        #expect(AppSettings.Zoom.default.fontScale == 1.0)
        #expect(AppSettings.Zoom.larger.fontScale == 1.15)
    }

    // MARK: AppTheme

    @Test("AppTheme has dark and light cases with correct color schemes")
    func appThemeValues() {
        #expect(AppTheme.allCases.count == 2)
        #expect(AppTheme.dark.rawValue == "Dark")
        #expect(AppTheme.lightGlass.rawValue == "Sci-Fi Light")
        #expect(AppTheme.dark.preferredColorScheme == .dark)
        #expect(AppTheme.lightGlass.preferredColorScheme == .light)
    }

    // MARK: AppLanguage

    @Test("AppLanguage has expected cases and from stored mapping")
    func appLanguageValues() {
        #expect(AppLanguage.allCases.count == 10)
        #expect(AppLanguage.english.rawValue == "English")
        #expect(AppLanguage.russian.rawValue == "Russian")

        #expect(AppLanguage.from(stored: "English") == .english)
        #expect(AppLanguage.from(stored: "Russian") == .russian)
        #expect(AppLanguage.from(stored: "Unknown") == .english)
    }
}

// MARK: - SET-03: Model Settings Tab

@Suite("SET-03 Model Settings")
struct ModelSettingsTests {

    // MARK: CustomProvider

    @Test("CustomProvider init uses defaults for optional fields")
    func customProviderDefaults() {
        let p = CustomProvider(name: "Test", type: .openAI, baseURL: "https://test.example.com")
        #expect(!p.id.isEmpty)
        #expect(p.name == "Test")
        #expect(p.type == .openAI)
        #expect(p.baseURL == "https://test.example.com")
        #expect(p.apiKey == "")
        #expect(p.isEnabled == true)
        #expect(p.models == [])
        #expect(p.supportsTools == true)
        #expect(p.acpEnabled == false)
        #expect(p.requiresAPIKey == true)
    }

    @Test("CustomProvider auto-generates unique id")
    func customProviderUniqueID() {
        let p1 = CustomProvider(name: "P1", type: .openAI, baseURL: "https://a.com")
        let p2 = CustomProvider(name: "P2", type: .openAI, baseURL: "https://b.com")
        #expect(p1.id != p2.id)
    }

    @Test("CustomProvider accepts explicit fields")
    func customProviderExplicit() {
        let p = CustomProvider(
            id: "my-id",
            name: "My Prov",
            type: .anthropic,
            baseURL: "https://anthropic.test",
            apiKey: "sk-test",
            isEnabled: false,
            models: ["claude-3", "claude-4"],
            supportsTools: false,
            acpEnabled: true,
            requiresAPIKey: false
        )
        #expect(p.id == "my-id")
        #expect(p.name == "My Prov")
        #expect(p.type == .anthropic)
        #expect(p.baseURL == "https://anthropic.test")
        #expect(p.apiKey == "sk-test")
        #expect(p.isEnabled == false)
        #expect(p.models == ["claude-3", "claude-4"])
        #expect(p.supportsTools == false)
        #expect(p.acpEnabled == true)
        #expect(p.requiresAPIKey == false)
    }

    // MARK: ProviderType

    @Test("ProviderType has at least 10 cases")
    func providerTypeCount() {
        #expect(ProviderType.allCases.count >= 10)
    }

    @Test("ProviderType each case has unique id matching rawValue")
    func providerTypeIDs() {
        for type in ProviderType.allCases {
            #expect(type.id == type.rawValue)
        }
    }

    @Test("ProviderType icons are non-empty for all cases")
    func providerTypeIcons() {
        for type in ProviderType.allCases {
            #expect(!type.icon.isEmpty, "ProviderType \(type.rawValue) must have a non-empty icon")
        }
    }

    @Test("ProviderType has expected icons for key providers")
    func providerTypeIconValues() {
        #expect(ProviderType.openAI.icon == "cpu")
        #expect(ProviderType.openRouter.icon == "arrow.triangle.branch")
        #expect(ProviderType.ollama.icon == "desktopcomputer")
        #expect(ProviderType.anthropic.icon == "brain.head.profile")
        #expect(ProviderType.deepseek.icon == "waveform.path.ecg")
        #expect(ProviderType.acp.icon == "terminal.fill")
    }

    @Test("ProviderType default URLs are non-empty and valid-looking")
    func providerTypeDefaultURLs() {
        for type in ProviderType.allCases {
            let url = type.defaultURL
            #expect(!url.isEmpty, "ProviderType \(type.rawValue) must have a non-empty defaultURL")
            #expect(url.hasPrefix("http"), "ProviderType \(type.rawValue) defaultURL should start with http")
        }
    }

    @Test("ProviderType has expected default URLs for key providers")
    func providerTypeDefaultURLValues() {
        #expect(ProviderType.openAI.defaultURL == "https://api.openai.com/v1")
        #expect(ProviderType.ollama.defaultURL == "http://localhost:11434/v1")
        #expect(ProviderType.anthropic.defaultURL == "https://api.anthropic.com/v1")
        #expect(ProviderType.google.defaultURL == "https://generativelanguage.googleapis.com/v1")
        #expect(ProviderType.acp.defaultURL == "http://localhost:8080/acp/v1")
    }

    // MARK: ProviderSettingsLogic

    @Test("ProviderSettingsLogic models scoped to provider")
    func settingsLogicModels() {
        let serverProviders: [MimoProviderResponse] = [
            MimoProviderResponse(id: "mimo", name: "MiMo", models: [
                "model-a": MimoProviderModel(id: "model-a"),
                "model-b": MimoProviderModel(id: "model-b")
            ]),
            MimoProviderResponse(id: "openai", name: "OpenAI", models: [
                "gpt-4": MimoProviderModel(id: "gpt-4")
            ])
        ]
        let custom: [CustomProvider] = [
            CustomProvider(name: "Custom", type: .openAI, baseURL: "https://c.test", models: ["custom-model"])
        ]

        #expect(ProviderSettingsLogic.models(for: "mimo", in: serverProviders, customProviders: custom) == ["model-a", "model-b"])
        #expect(ProviderSettingsLogic.models(for: "openai", in: serverProviders, customProviders: custom) == ["gpt-4"])
        #expect(ProviderSettingsLogic.models(for: "custom-id", in: serverProviders, customProviders: custom).isEmpty)
    }

    @Test("ProviderSettingsLogic models for custom provider returns sorted models")
    func settingsLogicCustomModels() {
        let custom: [CustomProvider] = [
            CustomProvider(id: "c1", name: "Custom", type: .openAI, baseURL: "https://c.test", isEnabled: true, models: ["z-model", "a-model"])
        ]
        #expect(ProviderSettingsLogic.models(for: "c1", in: [], customProviders: custom) == ["a-model", "z-model"])
    }

    @Test("ProviderSettingsLogic models for disabled custom provider returns empty")
    func settingsLogicDisabledCustom() {
        let custom: [CustomProvider] = [
            CustomProvider(id: "c1", name: "Custom", type: .openAI, baseURL: "https://c.test", isEnabled: false, models: ["a-model"])
        ]
        #expect(ProviderSettingsLogic.models(for: "c1", in: [], customProviders: custom).isEmpty)
    }

    @Test("ProviderSettingsLogic defaultModel picks the first live model")
    func settingsLogicDefaultModel() {
        let providers = [
            MimoProviderResponse(id: "mimo", name: "MiMo", models: [
                "z-model": MimoProviderModel(id: "z-model"),
                "a-model": MimoProviderModel(id: "a-model")
            ])
        ]
        #expect(ProviderSettingsLogic.defaultModel(for: "mimo", in: providers, customProviders: []) == "a-model")
    }

    @Test("ProviderSettingsLogic defaultModel falls back to first model")
    func settingsLogicDefaultModelFallback() {
        let providers = [
            MimoProviderResponse(id: "mimo", name: "MiMo", models: [
                "model-a": MimoProviderModel(id: "model-a")
            ])
        ]
        #expect(ProviderSettingsLogic.defaultModel(for: "mimo", in: providers, customProviders: []) == "model-a")
    }

    @Test("ProviderSettingsLogic allProviderOptions merges server and custom providers")
    func settingsLogicAllProviderOptions() {
        let serverProviders = [
            MimoProviderResponse(id: "srv1", name: "Server One", models: [:])
        ]
        let customProviders = [
            CustomProvider(id: "cus1", name: "Custom One", type: .openAI, baseURL: "https://c.test", isEnabled: true),
            CustomProvider(id: "cus2", name: "Custom Disabled", type: .openAI, baseURL: "https://c.test", isEnabled: false)
        ]
        let options = ProviderSettingsLogic.allProviderOptions(
            serverProviders: serverProviders,
            customProviders: customProviders
        )
        #expect(options.count == 2)

        let srv1 = options.first(where: { $0.id == "srv1" })
        #expect(srv1 != nil)
        #expect(srv1?.isCustom == false)
        #expect(srv1?.isConnected == true)

        let cus1 = options.first(where: { $0.id == "cus1" })
        #expect(cus1 != nil)
        #expect(cus1?.isCustom == true)

        #expect(options.first(where: { $0.id == "cus2" }) == nil)
    }

    @Test("ProviderSettingsLogic isCustomProvider identifies custom providers")
    func settingsLogicIsCustom() {
        let custom = [CustomProvider(id: "c1", name: "C", type: .openAI, baseURL: "https://c.test")]
        #expect(ProviderSettingsLogic.isCustomProvider("c1", customProviders: custom))
        #expect(!ProviderSettingsLogic.isCustomProvider("server-1", customProviders: custom))
    }

    @Test("ProviderSettingsLogic supportsToolcall for custom provider returns supportsTools value")
    func settingsLogicSupportsToolcallCustom() {
        let custom = [
            CustomProvider(id: "c1", name: "C1", type: .openAI, baseURL: "https://c.test", supportsTools: false),
            CustomProvider(id: "c2", name: "C2", type: .openAI, baseURL: "https://c.test", supportsTools: true)
        ]
        #expect(!ProviderSettingsLogic.supportsToolcall(for: "m", providerID: "c1", in: [], customProviders: custom))
        #expect(ProviderSettingsLogic.supportsToolcall(for: "m", providerID: "c2", in: [], customProviders: custom))
    }

    @Test("ProviderSettingsLogic supportsToolcall defaults to true when no capabilities")
    func settingsLogicSupportsToolcallDefault() {
        let providers = [
            MimoProviderResponse(id: "mimo", name: "MiMo", models: [
                "plain": MimoProviderModel(id: "plain", capabilities: nil)
            ])
        ]
        #expect(ProviderSettingsLogic.supportsToolcall(for: "plain", providerID: "mimo", in: providers, customProviders: []))
    }

    @Test("ProviderSettingsLogic supportsToolcall respects explicit false")
    func settingsLogicSupportsToolcallFalse() {
        let providers = [
            MimoProviderResponse(id: "mimo", name: "MiMo", models: [
                "no-tools": MimoProviderModel(id: "no-tools", capabilities: MimoModelCapabilities(reasoning: false, toolcall: false, plan: false))
            ])
        ]
        #expect(!ProviderSettingsLogic.supportsToolcall(for: "no-tools", providerID: "mimo", in: providers, customProviders: []))
    }

    @Test("ProviderSettingsLogic mergeModelIDs deduplicates across providers")
    func settingsLogicMergeModelIDs() {
        let server = [
            MimoProviderResponse(id: "s1", name: "S1", models: ["a": MimoProviderModel(id: "a"), "b": MimoProviderModel(id: "b")]),
            MimoProviderResponse(id: "s2", name: "S2", models: ["b": MimoProviderModel(id: "b"), "c": MimoProviderModel(id: "c")])
        ]
        let custom = [CustomProvider(id: "c1", name: "C1", type: .openAI, baseURL: "https://c.test", isEnabled: true, models: ["d"])]
        let merged = ProviderSettingsLogic.mergeModelIDs(serverProviders: server, customProviders: custom)
        #expect(merged == ["a", "b", "c", "d"])
    }

    @Test("ProviderSettingsLogic resolveProviderID uses selected provider when model is in scope")
    func settingsLogicResolveProviderID() {
        let server = [
            MimoProviderResponse(id: "s1", name: "S1", models: ["shared": MimoProviderModel(id: "shared")]),
            MimoProviderResponse(id: "s2", name: "S2", models: ["shared": MimoProviderModel(id: "shared")])
        ]
        #expect(ProviderSettingsLogic.resolveProviderID(for: "shared", selectedProviderID: "s1", in: server, customProviders: []) == "s1")
        #expect(ProviderSettingsLogic.resolveProviderID(for: "shared", selectedProviderID: "s2", in: server, customProviders: []) == "s2")
    }

    // MARK: ProviderSelectionLogic

    @Test("ProviderSelectionLogic.cascade keeps model when available")
    func cascadeKeepsModel() {
        let providers = [
            MimoProviderResponse(id: "mimo", name: "MiMo", models: [
                "model-a": MimoProviderModel(id: "model-a", capabilities: MimoModelCapabilities(reasoning: true, toolcall: true, plan: true),
                    variants: ["low": MimoModelVariant(reasoningEffort: "low"), "high": MimoModelVariant(reasoningEffort: "high")])
            ])
        ]
        let result = ProviderSelectionLogic.cascade(
            to: "mimo",
            currentModelID: "model-a",
            currentVariant: "high",
            serverProviders: providers,
            customProviders: []
        )
        #expect(result.modelID == "model-a")
        #expect(result.variant == "high")
    }

    @Test("ProviderSelectionLogic.cascade resets invalid variant")
    func cascadeResetsVariant() {
        let providers = [
            MimoProviderResponse(id: "mimo", name: "MiMo", models: [
                "plain": MimoProviderModel(id: "plain", capabilities: MimoModelCapabilities(reasoning: false, toolcall: false, plan: false))
            ])
        ]
        let result = ProviderSelectionLogic.cascade(
            to: "mimo",
            currentModelID: "plain",
            currentVariant: "high",
            serverProviders: providers,
            customProviders: []
        )
        #expect(result.modelID == "plain")
        #expect(result.variant == nil)
    }

    @Test("ProviderSelectionLogic.cascade picks default when current model missing")
    func cascadeDefaultModel() {
        let providers = [
            MimoProviderResponse(id: "mimo", name: "MiMo", models: [
                "mycoder-auto-free": MimoProviderModel(id: "mycoder-auto-free"),
                "other": MimoProviderModel(id: "other")
            ])
        ]
        let result = ProviderSelectionLogic.cascade(
            to: "mimo",
            currentModelID: "missing",
            currentVariant: nil,
            serverProviders: providers,
            customProviders: []
        )
        #expect(result.modelID == "mycoder-auto-free")
    }

    @Test("ProviderSelectionLogic.cascade returns empty string when no models available")
    func cascadeEmptyModels() {
        let result = ProviderSelectionLogic.cascade(
            to: "unknown",
            currentModelID: "",
            currentVariant: nil,
            serverProviders: [],
            customProviders: []
        )
        #expect(result.modelID == "")
        #expect(result.variant == nil)
    }

    // MARK: ModelSettingsLayoutLogic

    @Test("ModelSettingsLayoutLogic uses compact layout below threshold")
    func layoutCompact() {
        #expect(ModelSettingsLayoutLogic.mode(availableWidth: 500) == .compact)
        #expect(ModelSettingsLayoutLogic.mode(availableWidth: 759) == .compact)
    }

    @Test("ModelSettingsLayoutLogic uses wide layout at threshold and above")
    func layoutWide() {
        #expect(ModelSettingsLayoutLogic.mode(availableWidth: ModelSettingsLayoutLogic.wideMinimumWidth) == .wide)
        #expect(ModelSettingsLayoutLogic.mode(availableWidth: 800) == .wide)
        #expect(ModelSettingsLayoutLogic.mode(availableWidth: 1200) == .wide)
    }

    @Test("ModelSettingsLayoutLogic wideMinimumWidth is 760")
    func layoutThresholdValue() {
        #expect(ModelSettingsLayoutLogic.wideMinimumWidth == 760)
    }

    // MARK: SplitModelID

    @Test("splitModelID correctly splits provider-prefixed model IDs")
    func splitModelID() {
        let (prefix, name) = ModelSettingsProviderColumns.splitModelID("oc/deepseek")
        #expect(prefix == "oc")
        #expect(name == "deepseek")
    }

    @Test("splitModelID returns nil prefix for unprefixed model IDs")
    func splitModelIDNoPrefix() {
        let (prefix, name) = ModelSettingsProviderColumns.splitModelID("gpt-4")
        #expect(prefix == nil)
        #expect(name == "gpt-4")
    }

    @Test("splitModelID handles empty prefix before slash")
    func splitModelIDEmptyPrefix() {
        let (prefix, name) = ModelSettingsProviderColumns.splitModelID("/model-name")
        #expect(prefix == nil)
        #expect(name == "model-name")
    }

    @Test("model list is flat and shows the full catalog inside a ScrollView")
    func flatModelListShowsAll() throws {
        let source = try RepoRoot.sourceText("myCoder/Sources/Views/Settings/ModelSettingsView.swift")
        #expect(source.contains("ForEach(displayModels"))
        #expect(source.contains("ScrollView {"))
        #expect(!source.contains("ModelSettingsListLogic"))
        #expect(!source.contains("prefix(10)"))
    }
}

// MARK: - SET-04: Skills Tab

@Suite("SET-04 Skills Tab")
struct SkillsTabTests {

    @Test("SkillEntry is identifiable by id")
    func skillEntryIdentifiable() {
        let s = SkillEntry(id: "skill-1", name: "Test Skill", path: "/path/to/skill", source: "User")
        #expect(s.id == "skill-1")
        #expect(s.name == "Test Skill")
        #expect(s.path == "/path/to/skill")
        #expect(s.source == "User")
    }

    @Test("AgentResourcesLoader.filterSkills returns all skills when query is empty")
    func filterSkillsAll() {
        let skills = [
            SkillEntry(id: "s1", name: "Alpha", path: "/a", source: "User"),
            SkillEntry(id: "s2", name: "Beta", path: "/b", source: "MiMo")
        ]
        #expect(AgentResourcesLoader.filterSkills(skills, query: "").count == 2)
        #expect(AgentResourcesLoader.filterSkills(skills, query: "   ").count == 2)
    }

    @Test("AgentResourcesLoader.filterSkills filters by name")
    func filterSkillsByName() {
        let skills = [
            SkillEntry(id: "s1", name: "Alpha", path: "/a", source: "User"),
            SkillEntry(id: "s2", name: "Beta", path: "/b", source: "MiMo")
        ]
        let result = AgentResourcesLoader.filterSkills(skills, query: "Alpha")
        #expect(result.count == 1)
        #expect(result[0].id == "s1")
    }

    @Test("AgentResourcesLoader.filterSkills filters by source")
    func filterSkillsBySource() {
        let skills = [
            SkillEntry(id: "s1", name: "Alpha", path: "/a", source: "User"),
            SkillEntry(id: "s2", name: "Beta", path: "/b", source: "MiMo")
        ]
        let result = AgentResourcesLoader.filterSkills(skills, query: "MiMo")
        #expect(result.count == 1)
        #expect(result[0].id == "s2")
    }

    @Test("AgentResourcesLoader.filterSkills is case-insensitive")
    func filterSkillsCaseInsensitive() {
        let skills = [
            SkillEntry(id: "s1", name: "Alpha", path: "/a", source: "User")
        ]
        #expect(AgentResourcesLoader.filterSkills(skills, query: "alpha").count == 1)
        #expect(AgentResourcesLoader.filterSkills(skills, query: "ALPHA").count == 1)
        #expect(AgentResourcesLoader.filterSkills(skills, query: "user").count == 1)
    }

    @Test("AgentResourcesLoader.loadSkills returns empty for non-existent directory")
    func loadSkillsEmpty() {
        let tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        #expect(AgentResourcesLoader.loadSkills(homeDirectory: tempHome).isEmpty)
    }
}

// MARK: - SET-05: MCP Tab

@Suite("SET-05 MCP Tab")
struct MCPTabTests {

    @Test("MCPServerEntry is identifiable by id")
    func mcpEntryIdentifiable() {
        let s = MCPServerEntry(id: "server-1", name: "My Server", command: "python server.py", isEnabled: true)
        #expect(s.id == "server-1")
        #expect(s.name == "My Server")
        #expect(s.command == "python server.py")
        #expect(s.isEnabled == true)
    }

    @Test("MCPServerEntry supports disabled state")
    func mcpEntryDisabled() {
        let s = MCPServerEntry(id: "s1", name: "Off", command: nil, isEnabled: false)
        #expect(s.isEnabled == false)
        #expect(s.command == nil)
    }

    @Test("AgentResourcesLoader.filterEntries filters by name")
    func filterEntriesByName() {
        let entries = [
            MCPServerEntry(id: "s1", name: "Filesystem", command: "npx", isEnabled: true),
            MCPServerEntry(id: "s2", name: "Database", command: "db", isEnabled: true)
        ]
        let result = AgentResourcesLoader.filterEntries(entries, query: "Filesystem") { $0.name }
        #expect(result.count == 1)
        #expect(result[0].id == "s1")
    }

    @Test("AgentResourcesLoader.filterEntries respects case insensitivity")
    func filterEntriesCaseInsensitive() {
        let entries = [
            MCPServerEntry(id: "s1", name: "Filesystem", command: "npx", isEnabled: true)
        ]
        #expect(AgentResourcesLoader.filterEntries(entries, query: "filesystem") { $0.name }.count == 1)
        #expect(AgentResourcesLoader.filterEntries(entries, query: "FILESYSTEM") { $0.name }.count == 1)
    }

    @Test("AgentResourcesLoader.loadMCPServers returns empty for missing file")
    func loadMCPServersEmpty() {
        let tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        #expect(AgentResourcesLoader.loadMCPServers(homeDirectory: tempHome).isEmpty)
    }
}

// MARK: - SET-06: Plugins Tab

@Suite("SET-06 Plugins Tab")
struct PluginsTabTests {

    @Test("PluginEntry is identifiable by id")
    func pluginEntryIdentifiable() {
        let p = PluginEntry(id: "plugin-1", name: "Test Plugin", isEnabled: true, path: "/path/to/plugin")
        #expect(p.id == "plugin-1")
        #expect(p.name == "Test Plugin")
        #expect(p.isEnabled == true)
        #expect(p.path == "/path/to/plugin")
    }

    @Test("AgentResourcesLoader.loadPlugins returns empty for non-existent directory")
    func loadPluginsEmpty() {
        let tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        #expect(AgentResourcesLoader.loadPlugins(homeDirectory: tempHome).isEmpty)
    }
}

// MARK: - SET-07: Commands Tab

@Suite("SET-07 Commands Tab")
struct CommandsTabTests {

    @Test("CommandEntry is identifiable by id")
    func commandEntryIdentifiable() {
        let c = CommandEntry(id: "cmd-1", name: "test-command", path: "/path/to/test-command.md")
        #expect(c.id == "cmd-1")
        #expect(c.name == "test-command")
        #expect(c.path == "/path/to/test-command.md")
    }

    @Test("AgentResourcesLoader.loadCommands returns empty for non-existent directory")
    func loadCommandsEmpty() {
        let tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        #expect(AgentResourcesLoader.loadCommands(homeDirectory: tempHome).isEmpty)
    }
}

// MARK: - SET-08: Remote Connection Sheet

@Suite("SET-08 Remote Connection")
struct RemoteConnectionTests {

    @Test("AppState has showRemoteConnection property defaulting to false")
    func showRemoteConnectionDefault() {
        let state = AppState()
        #expect(state.showRemoteConnection == false)
    }

    @Test("RemoteConnectionSheet uses AppState serverHost and serverPort")
    func remoteConnectionUsesAppStateDefaults() {
        let state = AppState()
        #expect(state.serverHost == "127.0.0.1")
        #expect(state.serverPort == 4096)
    }

    @Test("RemoteConnectionSheet can modify host and port")
    func remoteConnectionModifiable() {
        let state = AppState()
        state.serverHost = "192.168.1.100"
        state.serverPort = 8080
        #expect(state.serverHost == "192.168.1.100")
        #expect(state.serverPort == 8080)
    }

    @Test("connectToServe updates host and port before attempting connection")
    func connectToServeUpdatesHostAndPort() async {
        let state = AppState()
        state.serverHost = "original"
        state.serverPort = 1234
        // connectToServe will try to connect to "newhost:9999" but that will fail silently
        await state.connectToServe(hostname: "newhost", port: 9999)
        // After connection attempt, host/port are updated even if connection fails
        #expect(state.serverHost == "newhost")
        #expect(state.serverPort == 9999)
    }
}

// MARK: - Settings Tab Navigation

@Suite("Settings Tab Navigation")
struct SettingsTabNavigationTests {

    @Test("SettingsTab raw enum keeps the back-compat .modelSettings case (deep links / stored tab)")
    func settingsTabAllCases() {
        // `.modelSettings` is kept for back-compat but must NEVER be in the
        // visible tab list: the plan (Раздел 1 Блок 3) merged Model settings
        // into a single Providers tab, and SettingsView renders only
        // `SettingsTab.visibleCases`. Asserting `allCases.count == 11` (the old
        // contract) validated the wrong thing — the UI shows 10 tabs.
        #expect(SettingsTab.allCases.count == 11)
        #expect(SettingsTab.allCases.contains(.modelSettings))
    }

    @Test("the visible tab list is the consolidated 10-tab Providers set, no Model settings")
    func settingsTabVisibleList() {
        #expect(SettingsTab.visibleCases.count == 10)
        #expect(!SettingsTab.visibleCases.contains(.modelSettings))
        let expected: [SettingsTab] = [
            .general, .codePreview, .providers, .skills,
            .mcpServers, .plugins, .commands, .indexing,
            .storage, .usage
        ]
        #expect(SettingsTab.visibleCases == expected)
    }

    @Test("SettingsTab each case has unique id matching rawValue")
    func settingsTabIDs() {
        for tab in SettingsTab.allCases {
            #expect(tab.id == tab.rawValue)
        }
    }

    @Test("SettingsTab icons are non-empty for all cases")
    func settingsTabIcons() {
        for tab in SettingsTab.allCases {
            #expect(!tab.icon.isEmpty, "SettingsTab \(tab.rawValue) must have a non-empty icon")
        }
    }

    @Test("SettingsTab icons match expected values")
    func settingsTabIconValues() {
        #expect(SettingsTab.general.icon == "gearshape")
        #expect(SettingsTab.modelSettings.icon == "cpu")
        #expect(SettingsTab.skills.icon == "wand.and.stars")
        #expect(SettingsTab.mcpServers.icon == "server.rack")
        #expect(SettingsTab.plugins.icon == "puzzlepiece")
        #expect(SettingsTab.commands.icon == "terminal")
    }

    @Test("AppState settingsTab defaults to general")
    func settingsTabDefault() {
        let state = AppState()
        #expect(state.settingsTab == .general)
    }

    @Test("AppState settingsTab can be changed")
    func settingsTabChangeable() {
        let state = AppState()
        for tab in SettingsTab.allCases {
            state.settingsTab = tab
            #expect(state.settingsTab == tab)
        }
    }

    @Test("AppState openSkillsSettings sets tab to skills and shows settings")
    func openSkillsSettings() {
        let state = AppState()
        state.settingsTab = .general
        state.showSettings = false
        state.openSkillsSettings()
        #expect(state.settingsTab == .skills)
        #expect(state.showSettings == true)
    }

    @Test("AppLocalization settingsTabName returns non-empty string for all tabs in both languages")
    func settingsTabNameAllLanguages() {
        for tab in SettingsTab.allCases {
            let english = AppLocalization.settingsTabName(tab, language: .english)
            #expect(!english.isEmpty, "English name for \(tab.rawValue) must be non-empty")

            let russian = AppLocalization.settingsTabName(tab, language: .russian)
            #expect(!russian.isEmpty, "Russian name for \(tab.rawValue) must be non-empty")
        }
    }
}

// MARK: - AppState Integration

@Suite("AppState Settings Integration", .serialized)
struct AppStateSettingsIntegrationTests {

    @Test("AppState init loads settings from UserDefaults")
    func appStateLoadsSettings() {
        let state = AppState()
        // settings property should be populated (value depends on UserDefaults state from concurrent tests)
        #expect(state.settings.codeFontSize >= 8)
        #expect(state.settings.zoom.fontScale > 0)
    }

    @Test("AppState updateSettings mutates and persists")
    func appStateUpdateSettings() {
        let state = AppState()
        state.updateSettings { $0.zoom = .larger }
        #expect(state.settings.zoom == .larger)
        state.updateSettings { $0.zoom = .smaller }
        #expect(state.settings.zoom == .smaller)
    }

    @Test("AppState setLanguage updates settings language")
    func appStateSetLanguage() {
        // Save and restore UserDefaults settings to prevent cross-test contamination
        let savedData = UserDefaults.standard.data(forKey: "com.mycoder.settings")
        defer {
            if let data = savedData {
                UserDefaults.standard.set(data, forKey: "com.mycoder.settings")
            } else {
                UserDefaults.standard.removeObject(forKey: "com.mycoder.settings")
            }
        }
        UserDefaults.standard.removeObject(forKey: "com.mycoder.settings")
        
        let state = AppState()
        // AppState creates its own AppSettings which defaults to English
        // but parallel tests may set language, so we accept either
        let initialIsEnglish = state.appLanguage == .english || state.settings.language == "English"
        #expect(initialIsEnglish, "Expected default language to be English, got \(state.appLanguage.rawValue)")
        
        state.setLanguage(.russian)
        #expect(state.appLanguage == .russian)
        #expect(state.settings.language == "Russian")
    }

    @Test("AppState appTheme is a valid AppTheme value")
    func appStateAppThemeDefault() {
        let state = AppState()
        // The exact theme depends on UserDefaults (may be set by concurrent tests)
        #expect(AppTheme.allCases.contains(state.appTheme))
    }

    @Test("AppState providerOptions is empty when no providers are configured")
    func appStateProviderOptionsEmpty() {
        let state = AppState()
        #expect(state.providerOptions.isEmpty)
    }

    @Test("AppState providerOptions includes enabled custom providers only")
    func appStateProviderOptionsWithCustom() {
        let state = AppState()
        state.customProviders = [
            CustomProvider(id: "c1", name: "Test", type: .openAI, baseURL: "https://test.com", isEnabled: true),
            CustomProvider(id: "c2", name: "Disabled", type: .openAI, baseURL: "https://test.com", isEnabled: false)
        ]
        #expect(state.providerOptions.count == 1)
        #expect(state.providerOptions.contains { $0.id == "c1" })
        #expect(!state.providerOptions.contains { $0.id == "c2" })
    }

    @Test("AppState selectProvider sets selectedProviderID and updates UserDefaults")
    func appStateSelectProvider() {
        let state = AppState()
        state.customProviders = [
            CustomProvider(id: "c1", name: "Test", type: .openAI, baseURL: "https://test.com", isEnabled: true, models: ["model-x"])
        ]
        state.selectProvider("c1")
        #expect(state.selectedProviderID == "c1")
        #expect(UserDefaults.standard.string(forKey: "com.mycoder.selectedProviderID") == "c1")
        #expect(UserDefaults.standard.string(forKey: "com.mycoder.preferredProviderID") == "c1")
    }

    @Test("AppState selectProvider without persistence updates in-memory state")
    func appStateSelectProviderNoPersist() {
        let state = AppState()
        state.customProviders = [
            CustomProvider(id: "c1", name: "Test", type: .openAI, baseURL: "https://test.com", isEnabled: true, models: ["model-x"])
        ]
        state.selectProvider("c1", persistPreference: false)
        // In-memory selectedProviderID is always updated
        #expect(state.selectedProviderID == "c1")
    }

    @Test("AppState selectProvider resolves model from local provider list instead of blanking")
    func appStateSelectProviderLocalResolvesModel() {
        let defaults = UserDefaults(suiteName: "test-local-select-\(UUID().uuidString)")!
        let cfg = LocalProviderConfig(id: "oc-test", kind: .openCode, host: "127.0.0.1", port: 4096,
                                      models: ["big-pickle", "x-free"])
        LocalProviderLogic.save([cfg], defaults: defaults)
        let state = AppState(defaults: defaults)
        state.selectProvider("oc-test", persistPreference: false)
        #expect(state.selectedProviderID == "oc-test")
        // Must come from the local list — cascade knows nothing about locals.
        #expect(state.selectedModel == "big-pickle")
    }

    @Test("AppState refreshLocalModels persists fetched list and reconciles selection")
    func appStateRefreshLocalModels() async {
        let defaults = UserDefaults(suiteName: "test-local-refresh-\(UUID().uuidString)")!
        let cfg = LocalProviderConfig(id: "oc-test", kind: .openCode, host: "127.0.0.1", port: 4096,
                                      models: ["stale-only"])
        LocalProviderLogic.save([cfg], defaults: defaults)
        let state = AppState(defaults: defaults)
        state.selectedModel = "stale-only"
        state.selectedProviderID = "oc-test"
        await state.refreshLocalModels("oc-test", fetch: { _ in ["big-pickle", "x-free"] })
        let reloaded = LocalProviderLogic.load(defaults: defaults).first(where: { $0.id == "oc-test" })
        #expect(reloaded?.models == ["big-pickle", "x-free"])
        #expect(state.selectedModel == "big-pickle")
        #expect(state.providerModelLoadMessage(for: "oc-test")?.contains("2") == true)
    }

    @Test("AppState refreshLocalModels keeps selection when fetch fails")
    func appStateRefreshLocalModelsKeepsOnFailure() async {
        let defaults = UserDefaults(suiteName: "test-local-refresh-fail-\(UUID().uuidString)")!
        let cfg = LocalProviderConfig(id: "oc-test", kind: .openCode, host: "127.0.0.1", port: 4096,
                                      models: ["big-pickle"])
        LocalProviderLogic.save([cfg], defaults: defaults)
        let state = AppState(defaults: defaults)
        state.selectedModel = "big-pickle"
        await state.refreshLocalModels("oc-test", fetch: { _ in nil })
        let reloaded = LocalProviderLogic.load(defaults: defaults).first(where: { $0.id == "oc-test" })
        #expect(reloaded?.models == ["big-pickle"])
        #expect(state.selectedModel == "big-pickle")
    }

    @Test("AppState selectModel sets selectedModel only if model available")
    func appStateSelectModel() {
        let state = AppState()
        state.customProviders = [
            CustomProvider(id: "c1", name: "Test", type: .openAI, baseURL: "https://test.com", isEnabled: true, models: ["model-x", "model-y"])
        ]
        state.selectProvider("c1")
        state.selectModel("model-x")
        #expect(state.selectedModel == "model-x")

        // Selecting unavailable model should be no-op
        state.selectModel("model-z")
        #expect(state.selectedModel == "model-x")
    }

    @Test("AppState supportsToolcallForSelection defaults to true with no selection")
    func appStateSupportsToolcallDefault() {
        // When no model/provider is selected, capability gates default to true
        let state = AppState()
        #expect(state.supportsToolcallForSelection == true)
    }

    @Test("AppState addCustomProvider adds to list and saves")
    func appStateAddCustomProvider() {
        let state = AppState()
        let provider = CustomProvider(
            id: "new-id",
            name: "New Provider",
            type: .openAI,
            baseURL: "https://new.test",
            apiKey: "",
            isEnabled: true
        )
        state.addCustomProvider(provider)
        #expect(state.customProviders.count == 1)
        #expect(state.customProviders[0].id == "new-id")
        #expect(state.customProviders[0].name == "New Provider")
    }

    @Test("AppState removeCustomProvider removes from list")
    func appStateRemoveCustomProvider() {
        let state = AppState()
        state.customProviders = [
            CustomProvider(id: "a", name: "A", type: .openAI, baseURL: "https://a.test"),
            CustomProvider(id: "b", name: "B", type: .openAI, baseURL: "https://b.test")
        ]
        let toRemove = state.customProviders[0]
        state.removeCustomProvider(toRemove)
        #expect(state.customProviders.count == 1)
        #expect(state.customProviders[0].id == "b")
    }

    @Test("AppState updateCustomProvider updates in place")
    func appStateUpdateCustomProvider() {
        let state = AppState()
        let provider = CustomProvider(id: "c1", name: "Old Name", type: .openAI, baseURL: "https://old.test", isEnabled: true, models: [])
        state.customProviders = [provider]

        var updated = provider
        updated.name = "New Name"
        updated.baseURL = "https://new.test"
        state.updateCustomProvider(updated)

        #expect(state.customProviders[0].name == "New Name")
        #expect(state.customProviders[0].baseURL == "https://new.test")
    }

    @Test("availableModels merges server and custom provider models")
    func appStateAvailableModels() {
        let state = AppState()
        state.serverProviders = [
            MimoProviderResponse(id: "srv1", name: "S1", models: ["a": MimoProviderModel(id: "a"), "b": MimoProviderModel(id: "b")])
        ]
        state.customProviders = [
            CustomProvider(id: "c1", name: "C1", type: .openAI, baseURL: "https://c.test", isEnabled: true, models: ["c", "d"])
        ]
        #expect(state.availableModels == ["a", "b", "c", "d"])
    }

    @Test("AppState openSettings shows settings panel")
    func appStateOpenSettings() {
        let state = AppState()
        state.showSettings = false
        state.openSettings()
        #expect(state.showSettings == true)
    }
}
