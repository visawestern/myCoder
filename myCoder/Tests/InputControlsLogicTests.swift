import Testing
import Foundation
@testable import myCoder

// MARK: - INP-13 / INP-03: InputLayout constants & layout

@Suite("InputLayout constants")
struct InputLayoutConstantsTests {

    @Test("Card max width is 520")
    func cardMaxWidth() {
        #expect(InputLayout.cardMaxWidth == 520)
    }

    @Test("Card content padding is 14")
    func cardContentPadding() {
        #expect(InputLayout.cardContentPadding == 14)
    }

    @Test("Capsule corner radius is 22")
    func capsuleCornerRadius() {
        #expect(InputLayout.capsuleCornerRadius == 22)
    }

    @Test("Text min height is 24")
    func textMinHeight() {
        #expect(InputLayout.textMinHeight == 24)
    }

    @Test("Text max height is 72")
    func textMaxHeight() {
        #expect(InputLayout.textMaxHeight == 72)
    }

    @Test("Compact text height is 36 and <= max")
    func compactTextHeight() {
        #expect(InputLayout.compactTextHeight == 36)
        #expect(InputLayout.compactTextHeight <= InputLayout.textMaxHeight)
    }

    @Test("Text line limit is 4")
    func textLineLimit() {
        #expect(InputLayout.textLineLimit == 4)
    }

    @Test("Toolbar vertical padding is 8")
    func toolbarVerticalPadding() {
        #expect(InputLayout.toolbarVerticalPadding == 8)
    }

    @Test("Toolbar horizontal padding is 12")
    func toolbarHorizontalPadding() {
        #expect(InputLayout.toolbarHorizontalPadding == 12)
    }

    @Test("Section spacing is 0")
    func sectionSpacing() {
        #expect(InputLayout.sectionSpacing == 0)
    }
}

// MARK: - INP-03: WorkspaceDropdown logic

@Suite("WorkspaceDropdown state management and search filtering")
struct WorkspaceDropdownLogicTests {

    private func makeWorkspaces() -> [Workspace] {
        [
            Workspace(id: "1", name: "tm3", path: "/test/tm3"),
            Workspace(id: "2", name: "ZCodeProject", path: "/test/zcode"),
            Workspace(id: "3", name: "mimo-macos", path: "/test/mimo")
        ]
    }

    @Test("Empty search text returns all workspaces")
    func emptySearchReturnsAll() {
        let workspaces = makeWorkspaces()
        let searchText = ""
        let filtered = searchText.isEmpty
            ? workspaces
            : workspaces.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        #expect(filtered.count == 3)
    }

    @Test("Search text filters workspaces by name")
    func searchFiltersByName() {
        let workspaces = makeWorkspaces()
        let searchText = "tm"
        let filtered = workspaces.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        #expect(filtered.count == 1)
        #expect(filtered[0].name == "tm3")
    }

    @Test("Search is case insensitive")
    func searchIsCaseInsensitive() {
        let workspaces = makeWorkspaces()
        let searchText = "zcode"
        let filtered = workspaces.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        #expect(filtered.count == 1)
        #expect(filtered[0].name == "ZCodeProject")
    }

    @Test("Search with partial match finds workspaces")
    func searchPartialMatch() {
        let workspaces = makeWorkspaces()
        let searchText = "mimo"
        let filtered = workspaces.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        #expect(filtered.count == 1)
        #expect(filtered[0].name == "mimo-macos")
    }

    @Test("Search text with no matches returns empty")
    func searchNoMatchReturnsEmpty() {
        let workspaces = makeWorkspaces()
        let searchText = "nonexistent"
        let filtered = workspaces.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        #expect(filtered.isEmpty)
    }

    @Test("Workspace with empty name is not matched by search")
    func searchEmptyNameNotMatched() {
        let workspaces = [
            Workspace(id: "4", name: "", path: "/test/empty")
        ]
        let searchText = "test"
        let filtered = workspaces.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        #expect(filtered.isEmpty)
    }

    @Test("Multiple workspaces can match same search term")
    func searchMultipleMatches() {
        let workspaces = [
            Workspace(id: "1", name: "Project Alpha", path: "/a"),
            Workspace(id: "2", name: "Alpha Beta", path: "/b"),
            Workspace(id: "3", name: "Gamma", path: "/c")
        ]
        let searchText = "alpha"
        let filtered = workspaces.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        #expect(filtered.count == 2)
    }
}

// MARK: - INP-04: AccessLevel model

@Suite("AccessLevel enum")
struct AccessLevelModelTests {

    @Test("All cases exist and raw values match")
    func allCasesAndRawValues() {
        #expect(AccessLevel.askBeforeChanges.rawValue == "Ask before changes")
        #expect(AccessLevel.editAutomatically.rawValue == "Edit automatically")
        #expect(AccessLevel.fullAccess.rawValue == "Full access")
        #expect(AccessLevel.allCases.count == 3)
    }

    @Test("Descriptions are unique and non-empty per case")
    func descriptions() {
        let ask = AccessLevel.askBeforeChanges
        let edit = AccessLevel.editAutomatically
        let full = AccessLevel.fullAccess

        #expect(ask.description == "Ask before file changes.")
        #expect(edit.description == "Edit files automatically.")
        #expect(full.description == "Run with fewer confirmations.")

        let descriptions = Set(AccessLevel.allCases.map(\.description))
        #expect(descriptions.count == AccessLevel.allCases.count)
    }

    @Test("Icons are unique and non-empty per case")
    func icons() {
        #expect(AccessLevel.askBeforeChanges.icon == "hand.raised")
        #expect(AccessLevel.editAutomatically.icon == "pencil")
        #expect(AccessLevel.fullAccess.icon == "bolt.fill")

        let icons = Set(AccessLevel.allCases.map(\.icon))
        #expect(icons.count == AccessLevel.allCases.count)
    }

    @Test("Identifiable id matches rawValue")
    func identifiableID() {
        for level in AccessLevel.allCases {
            #expect(level.id == level.rawValue)
        }
    }

    @Test("RawValue initializer round-trips correctly")
    func rawValueRoundTrip() {
        for level in AccessLevel.allCases {
            let reconstructed = AccessLevel(rawValue: level.rawValue)
            #expect(reconstructed == level)
        }
    }

    @Test("Invalid raw value produces nil")
    func invalidRawValueNil() {
        #expect(AccessLevel(rawValue: "Not a real level") == nil)
    }

    @Test("CaseIterable ordering is preserved")
    func caseIterableOrdering() {
        let cases = AccessLevel.allCases
        #expect(cases[0] == .askBeforeChanges)
        #expect(cases[1] == .editAutomatically)
        #expect(cases[2] == .fullAccess)
    }
}

// MARK: - INP-05: AgentMode model

@Suite("AgentMode enum")
struct AgentModeModelTests {

    @Test("All cases exist and raw values match")
    func allCasesAndRawValues() {
        #expect(AgentMode.build.rawValue == "Build")
        #expect(AgentMode.plan.rawValue == "Plan")
        #expect(AgentMode.compose.rawValue == "Compose")
        #expect(AgentMode.allCases.count == 3)
    }

    @Test("Icons are unique and non-empty per case")
    func icons() {
        #expect(AgentMode.build.icon == "hammer.fill")
        #expect(AgentMode.plan.icon == "text.book.closed")
        #expect(AgentMode.compose.icon == "square.and.pencil")

        let icons = Set(AgentMode.allCases.map(\.icon))
        #expect(icons.count == AgentMode.allCases.count)
    }

    @Test("Identifiable id matches rawValue")
    func identifiableID() {
        for mode in AgentMode.allCases {
            #expect(mode.id == mode.rawValue)
        }
    }

    @Test("RawValue initializer round-trips correctly")
    func rawValueRoundTrip() {
        for mode in AgentMode.allCases {
            let reconstructed = AgentMode(rawValue: mode.rawValue)
            #expect(reconstructed == mode)
        }
    }

    @Test("Invalid raw value produces nil")
    func invalidRawValueNil() {
        #expect(AgentMode(rawValue: "Not a mode") == nil)
    }

    @Test("CaseIterable ordering is preserved")
    func caseIterableOrdering() {
        let cases = AgentMode.allCases
        #expect(cases[0] == .build)
        #expect(cases[1] == .plan)
        #expect(cases[2] == .compose)
    }
}

// MARK: - INP-05: Agent mode plan capability checking (ProviderCapabilityGates)

@Suite("Plan agent capability gates")
struct PlanAgentCapabilityTests {

    private func makeProvider(id: String = "mimo", models: [String: MimoProviderModel] = [:]) -> MimoProviderResponse {
        MimoProviderResponse(id: id, name: id.capitalized, models: models)
    }

    @Test("canSelectPlanAgent returns true when capabilities is nil (default)")
    func canSelectPlanWhenCapabilitiesNil() {
        let model = MimoProviderModel(id: "default-model")
        let provider = makeProvider(models: ["default-model": model])
        #expect(ProviderCapabilityGates.canSelectPlanAgent(
            modelID: "default-model", providerID: nil, providers: [provider], customProviders: []
        ))
    }

    @Test("canSelectPlanAgent returns false when plan is explicitly false")
    func canSelectPlanWhenPlanExplicitlyFalse() {
        let model = MimoProviderModel(
            id: "no-plan-model",
            capabilities: MimoModelCapabilities(reasoning: nil, toolcall: nil, plan: false)
        )
        let provider = makeProvider(models: ["no-plan-model": model])
        #expect(!ProviderCapabilityGates.canSelectPlanAgent(
            modelID: "no-plan-model", providerID: nil, providers: [provider], customProviders: []
        ))
    }

    @Test("canSelectPlanAgent returns true when plan is explicitly true")
    func canSelectPlanWhenPlanExplicitlyTrue() {
        let model = MimoProviderModel(
            id: "plan-model",
            capabilities: MimoModelCapabilities(plan: true)
        )
        let provider = makeProvider(models: ["plan-model": model])
        #expect(ProviderCapabilityGates.canSelectPlanAgent(
            modelID: "plan-model", providerID: nil, providers: [provider], customProviders: []
        ))
    }

    @Test("canSelectPlanAgent returns true when plan is nil but reasoning is true")
    func canSelectPlanWhenReasoningTrue() {
        let model = MimoProviderModel(
            id: "reasoning-model",
            capabilities: MimoModelCapabilities(reasoning: true)
        )
        let provider = makeProvider(models: ["reasoning-model": model])
        #expect(ProviderCapabilityGates.canSelectPlanAgent(
            modelID: "reasoning-model", providerID: nil, providers: [provider], customProviders: []
        ))
    }

    @Test("canSelectPlanAgent returns true for custom providers")
    func canSelectPlanForCustomProvider() {
        let custom = CustomProvider(
            id: "custom-llm", name: "My LLM", type: .openAI, baseURL: "http://localhost",
            models: ["my-model"], supportsTools: true
        )
        #expect(ProviderCapabilityGates.canSelectPlanAgent(
            modelID: "my-model", providerID: "custom-llm", providers: [], customProviders: [custom]
        ))
    }

    @Test("planAgentDisabledReason returns nil when plan is available")
    func planAgentDisabledReasonNil() {
        let model = MimoProviderModel(id: "capable-model", capabilities: MimoModelCapabilities(plan: true))
        let provider = makeProvider(models: ["capable-model": model])
        let reason = ProviderCapabilityGates.planAgentDisabledReason(
            modelID: "capable-model", providerID: nil, providers: [provider], customProviders: []
        )
        #expect(reason == nil)
    }

    @Test("planAgentDisabledReason returns message when plan is unavailable")
    func planAgentDisabledReasonMessage() {
        let model = MimoProviderModel(
            id: "basic-model",
            capabilities: MimoModelCapabilities(reasoning: false, toolcall: false, plan: false)
        )
        let provider = makeProvider(models: ["basic-model": model])
        let reason = ProviderCapabilityGates.planAgentDisabledReason(
            modelID: "basic-model", providerID: nil, providers: [provider], customProviders: []
        )
        #expect(reason == "This model does not support Plan mode.")
    }
}

// MARK: - INP-06: Provider selector logic

@Suite("Provider selection and resolution logic")
struct ProviderSelectionLogicTests {

    private func makeProvider(
        id: String = "mimo",
        models: [String: MimoProviderModel] = [:]
    ) -> MimoProviderResponse {
        MimoProviderResponse(id: id, name: id.capitalized, models: models)
    }

    private func makeModel(
        id: String,
        capabilities: MimoModelCapabilities? = nil
    ) -> MimoProviderModel {
        MimoProviderModel(id: id, capabilities: capabilities)
    }

    // MARK: - ProviderSettingsLogic.resolveProviderID

    @Test("resolveProviderID returns selected provider when it contains the model")
    func resolveProviderIDUsesSelected() {
        let provider = makeProvider(id: "mimo", models: [
            "mycoder-auto-free": makeModel(id: "mycoder-auto-free")
        ])
        let result = ProviderSettingsLogic.resolveProviderID(
            for: "mycoder-auto-free",
            selectedProviderID: "mimo",
            in: [provider],
            customProviders: []
        )
        #expect(result == "mimo")
    }

    @Test("resolveProviderID falls back to server provider when selected does not contain model")
    func resolveProviderIDFallsBackToServer() {
        let providerA = makeProvider(id: "provider-a", models: [
            "model-x": makeModel(id: "model-x")
        ])
        let providerB = makeProvider(id: "provider-b", models: [
            "model-y": makeModel(id: "model-y")
        ])
        // Selected is provider-b, model is only in provider-a
        let result = ProviderSettingsLogic.resolveProviderID(
            for: "model-x",
            selectedProviderID: "provider-b",
            in: [providerA, providerB],
            customProviders: []
        )
        #expect(result == "provider-a")
    }

    @Test("resolveProviderID falls back to custom provider when server has no match")
    func resolveProviderIDFallsBackToCustom() {
        let custom = CustomProvider(
            id: "my-local", name: "Local", type: .ollama, baseURL: "http://localhost:11434",
            models: ["local-model"], supportsTools: true
        )
        let result = ProviderSettingsLogic.resolveProviderID(
            for: "local-model",
            selectedProviderID: "",
            in: [],
            customProviders: [custom]
        )
        #expect(result == "my-local")
    }

    @Test("resolveProviderID returns nil when modelID is empty")
    func resolveProviderIDEmptyModel() {
        let result = ProviderSettingsLogic.resolveProviderID(
            for: "",
            selectedProviderID: "mimo",
            in: [],
            customProviders: []
        )
        #expect(result == nil)
    }

    @Test("resolveProviderID returns nil when no provider has the model")
    func resolveProviderIDNoMatch() {
        let result = ProviderSettingsLogic.resolveProviderID(
            for: "unknown-model",
            selectedProviderID: "",
            in: [],
            customProviders: []
        )
        #expect(result == nil)
    }

    // MARK: - ProviderSelectionLogic.cascade

    @Test("Cascade keeps current model when new provider contains it")
    func cascadeKeepsCurrentModel() {
        let provider = makeProvider(id: "mimo", models: [
            "mycoder-auto-free": makeModel(id: "mycoder-auto-free"),
            "other-model": makeModel(id: "other-model")
        ])
        let result = ProviderSelectionLogic.cascade(
            to: "mimo",
            currentModelID: "mycoder-auto-free",
            currentVariant: nil,
            serverProviders: [provider],
            customProviders: []
        )
        #expect(result.providerID == "mimo")
        #expect(result.modelID == "mycoder-auto-free")
    }

    @Test("Cascade selects default model when current model is not in new provider")
    func cascadeSelectsDefault() {
        let providerA = makeProvider(id: "provider-a", models: [
            "model-a": makeModel(id: "model-a")
        ])
        let providerB = makeProvider(id: "provider-b", models: [
            "mycoder-auto-free": makeModel(id: "mycoder-auto-free"),
            "model-b": makeModel(id: "model-b")
        ])
        let result = ProviderSelectionLogic.cascade(
            to: "provider-b",
            currentModelID: "model-a",
            currentVariant: nil,
            serverProviders: [providerA, providerB],
            customProviders: []
        )
        #expect(result.providerID == "provider-b")
        #expect(result.modelID == "model-b")
    }

    @Test("Cascade picks first model when no default exists and current is absent")
    func cascadePicksFirstModel() {
        let provider = makeProvider(id: "new-provider", models: [
            "alpha": makeModel(id: "alpha"),
            "beta": makeModel(id: "beta")
        ])
        let result = ProviderSelectionLogic.cascade(
            to: "new-provider",
            currentModelID: "unknown",
            currentVariant: nil,
            serverProviders: [provider],
            customProviders: []
        )
        #expect(result.providerID == "new-provider")
        #expect(result.modelID == "alpha") // First sorted: "alpha" < "beta"
    }

    @Test("Cascade returns empty modelID when provider has no models")
    func cascadeEmptyModels() {
        let provider = makeProvider(id: "empty-provider", models: [:])
        let result = ProviderSelectionLogic.cascade(
            to: "empty-provider",
            currentModelID: "anything",
            currentVariant: nil,
            serverProviders: [provider],
            customProviders: []
        )
        #expect(result.providerID == "empty-provider")
        #expect(result.modelID == "")
    }

    // MARK: - ProviderSettingsLogic.isCustomProvider

    @Test("isCustomProvider returns true for custom provider ID")
    func isCustomProviderTrue() {
        let custom = CustomProvider(id: "my-custom", name: "Custom", type: .openAI, baseURL: "http://localhost")
        #expect(ProviderSettingsLogic.isCustomProvider("my-custom", customProviders: [custom]))
    }

    @Test("isCustomProvider returns false for non-custom provider ID")
    func isCustomProviderFalse() {
        let custom = CustomProvider(id: "my-custom", name: "Custom", type: .openAI, baseURL: "http://localhost")
        #expect(!ProviderSettingsLogic.isCustomProvider("server-provider", customProviders: [custom]))
    }

    // MARK: - ProviderSettingsLogic.supportsReasoning

    @Test("supportsReasoning returns true when capabilities.reasoning is true")
    func supportsReasoningTrue() {
        let model = makeModel(id: "reason-model", capabilities: MimoModelCapabilities(reasoning: true))
        let provider = makeProvider(models: ["reason-model": model])
        #expect(ProviderSettingsLogic.supportsReasoning(for: "reason-model", in: [provider]))
    }

    @Test("supportsReasoning returns false when capabilities.reasoning is false")
    func supportsReasoningFalse() {
        let model = makeModel(id: "no-reason-model", capabilities: MimoModelCapabilities(reasoning: false))
        let provider = makeProvider(models: ["no-reason-model": model])
        #expect(!ProviderSettingsLogic.supportsReasoning(for: "no-reason-model", in: [provider]))
    }

    @Test("supportsReasoning returns false for custom providers")
    func supportsReasoningCustomProvider() {
        let custom = CustomProvider(id: "custom", name: "Custom", type: .openAI, baseURL: "http://localhost")
        #expect(!ProviderSettingsLogic.supportsReasoning(
            for: "some-model", in: [], providerID: "custom", customProviders: [custom]
        ))
    }

    // MARK: - ProviderSettingsLogic.supportsToolcall

    @Test("supportsToolcall returns custom provider supportsTools value")
    func supportsToolcallCustomProvider() {
        let custom = CustomProvider(
            id: "custom", name: "Custom", type: .openAI, baseURL: "http://localhost",
            supportsTools: false
        )
        #expect(!ProviderSettingsLogic.supportsToolcall(
            for: "some-model", providerID: "custom", in: [], customProviders: [custom]
        ))
    }

    @Test("supportsToolcall returns true when capabilities is nil (default)")
    func supportsToolcallDefaultTrue() {
        let model = makeModel(id: "default-model")
        let provider = makeProvider(models: ["default-model": model])
        #expect(ProviderSettingsLogic.supportsToolcall(
            for: "default-model", providerID: nil, in: [provider], customProviders: []
        ))
    }

    @Test("supportsToolcall returns false when toolcall is explicitly false")
    func supportsToolcallExplicitFalse() {
        let model = makeModel(id: "no-tool-model", capabilities: MimoModelCapabilities(toolcall: false))
        let provider = makeProvider(models: ["no-tool-model": model])
        #expect(!ProviderSettingsLogic.supportsToolcall(
            for: "no-tool-model", providerID: nil, in: [provider], customProviders: []
        ))
    }

    // MARK: - ProviderSettingsLogic.allProviderOptions

    @Test("allProviderOptions includes server and enabled custom providers")
    func allProviderOptions() {
        let server = makeProvider(id: "server-provider")
        let custom = CustomProvider(id: "custom", name: "My Custom", type: .openAI, baseURL: "http://localhost", isEnabled: true)
        let options = ProviderSettingsLogic.allProviderOptions(serverProviders: [server], customProviders: [custom])
        #expect(options.count == 2)
        #expect(options.contains(where: { $0.id == "server-provider" && !$0.isCustom }))
        #expect(options.contains(where: { $0.id == "custom" && $0.isCustom }))
    }

    @Test("allProviderOptions excludes disabled custom providers")
    func allProviderOptionsExcludesDisabled() {
        let custom = CustomProvider(id: "custom", name: "Disabled", type: .openAI, baseURL: "http://localhost", isEnabled: false)
        let options = ProviderSettingsLogic.allProviderOptions(serverProviders: [], customProviders: [custom])
        #expect(options.isEmpty)
    }
}

// MARK: - INP-10: SendReadinessLogic

@Suite("SendReadinessLogic")
struct SendReadinessLogicTests {

    // MARK: - connectionValidationError

    @Test("connectionValidationError nil when server is connected")
    func connectionValidServerConnected() {
        let error = SendReadinessLogic.connectionValidationError(serverConnected: true, selectedProviderID: "mimo")
        #expect(error == nil)
    }

    @Test("connectionValidationError returns error when server is disconnected with no provider")
    func connectionErrorDisconnectedNoProvider() {
        let error = SendReadinessLogic.connectionValidationError(
            serverConnected: false, selectedProviderID: "", customProviders: []
        )
        #expect(error != nil)
        #expect(error == "No provider is ready. Connect the local agent, add a custom provider, configure a local model, or connect a web provider.")
    }

    @Test("connectionValidationError nil when custom provider does not require API key")
    func connectionValidCustomProviderNoAPIKey() {
        let custom = CustomProvider(
            id: "local-llm", name: "Local", type: .ollama, baseURL: "http://localhost:11434",
            apiKey: "", isEnabled: true, requiresAPIKey: false
        )
        let error = SendReadinessLogic.connectionValidationError(
            serverConnected: false, selectedProviderID: "local-llm", customProviders: [custom]
        )
        #expect(error == nil)
    }

    @Test("connectionValidationError returns error when custom provider requires API key and server is disconnected")
    func connectionErrorCustomProviderRequiresAPIKey() {
        let custom = CustomProvider(
            id: "remote-llm", name: "Remote", type: .openAI, baseURL: "https://api.example.com",
            apiKey: "", isEnabled: true, requiresAPIKey: true
        )
        let error = SendReadinessLogic.connectionValidationError(
            serverConnected: false, selectedProviderID: "remote-llm", customProviders: [custom]
        )
        #expect(error != nil)
    }

    @Test("connectionValidationError returns error when custom provider is disabled")
    func connectionErrorCustomProviderDisabled() {
        let custom = CustomProvider(
            id: "disabled-llm", name: "Disabled", type: .openAI, baseURL: "http://localhost",
            apiKey: "", isEnabled: false, requiresAPIKey: false
        )
        let error = SendReadinessLogic.connectionValidationError(
            serverConnected: false, selectedProviderID: "disabled-llm", customProviders: [custom]
        )
        #expect(error != nil)
    }

    @Test("connectionValidationError returns error when selectedProviderID does not match any custom provider")
    func connectionErrorProviderIDNotFound() {
        let error = SendReadinessLogic.connectionValidationError(
            serverConnected: false, selectedProviderID: "nonexistent", customProviders: []
        )
        #expect(error != nil)
    }

    @Test("myCoder Auto Free is not ready without an available anonymous free catalog")
    func autoFreeRequiresAvailableCatalog() {
        let error = SendReadinessLogic.connectionValidationError(
            serverConnected: false,
            selectedProviderID: MyCoderAutoFreeProvider.builtInID,
            autoFreeReady: false
        )
        #expect(error?.contains("anonymous OpenCode free catalog") == true)
    }

    // MARK: - sendValidationError

    @Test("sendValidationError nil when model and provider are valid")
    func sendValid() {
        let error = SendReadinessLogic.sendValidationError(modelID: "gpt-4", providerID: "openai")
        #expect(error == nil)
    }

    @Test("sendValidationError returns error when model is empty")
    func sendErrorEmptyModel() {
        let error = SendReadinessLogic.sendValidationError(modelID: "  ", providerID: "openai")
        #expect(error == "Select a model before sending.")
    }

    @Test("sendValidationError returns error when model is only whitespace")
    func sendErrorWhitespaceModel() {
        let error = SendReadinessLogic.sendValidationError(modelID: "   \n  ", providerID: "openai")
        #expect(error == "Select a model before sending.")
    }

    @Test("sendValidationError returns error when providerID is nil")
    func sendErrorNilProvider() {
        let error = SendReadinessLogic.sendValidationError(modelID: "gpt-4", providerID: nil)
        #expect(error == "Select a provider for this model.")
    }

    @Test("sendValidationError returns error when providerID is empty")
    func sendErrorEmptyProvider() {
        let error = SendReadinessLogic.sendValidationError(modelID: "gpt-4", providerID: "")
        #expect(error == "Select a provider for this model.")
    }

    @Test("sendValidationError returns error when providerID is only whitespace")
    func sendErrorWhitespaceProvider() {
        let error = SendReadinessLogic.sendValidationError(modelID: "gpt-4", providerID: "  \n  ")
        #expect(error == "Select a provider for this model.")
    }

    // MARK: - canSendMessage

    @Test("canSendMessage true when all conditions are met")
    func canSendAllValid() {
        let result = SendReadinessLogic.canSendMessage(
            text: "Hello",
            images: [],
            files: [],
            modelID: "gpt-4",
            providerID: "openai",
            serverConnected: true
        )
        #expect(result)
    }

    @Test("canSendMessage false when text is empty and no attachments")
    func canSendEmptyTextNoAttachments() {
        let result = SendReadinessLogic.canSendMessage(
            text: "",
            images: [],
            files: [],
            modelID: "gpt-4",
            providerID: "openai",
            serverConnected: true
        )
        #expect(!result)
    }

    @Test("canSendMessage true when text is empty but has images")
    func canSendWithImages() {
        let images = [ClipboardImage(base64: "iVBORw0KGgo=", mimeType: "image/png")]
        let result = SendReadinessLogic.canSendMessage(
            text: "",
            images: images,
            files: [],
            modelID: "gpt-4",
            providerID: "openai",
            serverConnected: true
        )
        #expect(result)
    }

    @Test("canSendMessage true when text is empty but has files")
    func canSendWithFiles() {
        let files = [FileInfo(name: "test.txt", type: .swift)]
        let result = SendReadinessLogic.canSendMessage(
            text: "",
            images: [],
            files: files,
            modelID: "gpt-4",
            providerID: "openai",
            serverConnected: true
        )
        #expect(result)
    }

    @Test("canSendMessage false when model is empty")
    func canSendNoModel() {
        let result = SendReadinessLogic.canSendMessage(
            text: "Hello",
            images: [],
            files: [],
            modelID: "",
            providerID: "openai",
            serverConnected: true
        )
        #expect(!result)
    }

    @Test("canSendMessage false when provider is nil")
    func canSendNoProvider() {
        let result = SendReadinessLogic.canSendMessage(
            text: "Hello",
            images: [],
            files: [],
            modelID: "gpt-4",
            providerID: nil,
            serverConnected: true
        )
        #expect(!result)
    }

    @Test("canSendMessage false when server is disconnected and no valid custom provider")
    func canSendServerDisconnected() {
        let result = SendReadinessLogic.canSendMessage(
            text: "Hello",
            images: [],
            files: [],
            modelID: "gpt-4",
            providerID: "openai",
            serverConnected: false,
            customProviders: []
        )
        #expect(!result)
    }

    @Test("canSendMessage true with custom provider that does not require API key and server is disconnected")
    func canSendCustomProviderNoAPIKey() {
        let custom = CustomProvider(
            id: "local", name: "Local", type: .ollama, baseURL: "http://localhost",
            isEnabled: true, requiresAPIKey: false
        )
        let result = SendReadinessLogic.canSendMessage(
            text: "Hello",
            images: [],
            files: [],
            modelID: "local-model",
            providerID: "local",
            serverConnected: false,
            customProviders: [custom]
        )
        #expect(result)
    }

    @Test("canSendMessage false when everything else is valid but text is whitespace only")
    func canSendWhitespaceOnly() {
        let result = SendReadinessLogic.canSendMessage(
            text: "   \n  ",
            images: [],
            files: [],
            modelID: "gpt-4",
            providerID: "openai",
            serverConnected: true
        )
        #expect(!result)
    }

    @Test("canSendMessage false when server disconnected and custom provider is disabled")
    func canSendDisabledCustomProvider() {
        let custom = CustomProvider(
            id: "local", name: "Local", type: .ollama, baseURL: "http://localhost",
            isEnabled: false, requiresAPIKey: false
        )
        let result = SendReadinessLogic.canSendMessage(
            text: "Hello",
            images: [],
            files: [],
            modelID: "local-model",
            providerID: "local",
            serverConnected: false,
            customProviders: [custom]
        )
        #expect(!result)
    }
}

// MARK: - INP-04: AccessLevelPermissionLogic

@Suite("AccessLevelPermissionLogic")
struct AccessLevelPermissionLogicCoverageTests {

    @Test("permissionPatch for askBeforeChanges returns edit=ask")
    func permissionPatchAskBeforeChanges() {
        let patch = AccessLevelPermissionLogic.permissionPatch(for: .askBeforeChanges)
        #expect(patch["edit"] as? String == "ask")
        #expect(patch.count == 1)
    }

    @Test("permissionPatch for editAutomatically returns edit=allow")
    func permissionPatchEditAutomatically() {
        let patch = AccessLevelPermissionLogic.permissionPatch(for: .editAutomatically)
        #expect(patch["edit"] as? String == "allow")
        #expect(patch.count == 1)
    }

    @Test("permissionPatch for fullAccess returns all permissions")
    func permissionPatchFullAccess() {
        let patch = AccessLevelPermissionLogic.permissionPatch(for: .fullAccess)
        #expect(patch["edit"] as? String == "allow")
        #expect(patch["bash"] as? String == "allow")
        #expect(patch["webfetch"] as? String == "allow")
        #expect(patch["external_directory"] as? String == "allow")
        #expect(patch.count == 4)
    }

    @Test("accessLevel from nil permissions returns askBeforeChanges")
    func accessLevelNilReturnsAsk() {
        let level = AccessLevelPermissionLogic.accessLevel(from: nil)
        #expect(level == .askBeforeChanges)
    }

    @Test("accessLevel from empty permissions returns askBeforeChanges")
    func accessLevelEmptyReturnsAsk() {
        let level = AccessLevelPermissionLogic.accessLevel(from: [:])
        #expect(level == .askBeforeChanges)
    }

    @Test("accessLevel with edit=allow only returns editAutomatically")
    func accessLevelEditOnly() {
        let level = AccessLevelPermissionLogic.accessLevel(from: ["edit": "allow"])
        #expect(level == .editAutomatically)
    }

    @Test("accessLevel with edit=allow and bash=allow returns fullAccess")
    func accessLevelEditAndBash() {
        let level = AccessLevelPermissionLogic.accessLevel(from: ["edit": "allow", "bash": "allow"])
        #expect(level == .fullAccess)
    }

    @Test("accessLevel with edit=ask returns askBeforeChanges")
    func accessLevelEditAsk() {
        let level = AccessLevelPermissionLogic.accessLevel(from: ["edit": "ask"])
        #expect(level == .askBeforeChanges)
    }

    @Test("migrateLegacyAccessLevel plan mode returns askBeforeChanges")
    func migratePlanMode() {
        let level = AccessLevelPermissionLogic.migrateLegacyAccessLevel(raw: "Plan mode")
        #expect(level == .askBeforeChanges)
    }

    @Test("migrateLegacyAccessLevel valid raw values map correctly")
    func migrateValidRawValues() {
        let ask = AccessLevelPermissionLogic.migrateLegacyAccessLevel(raw: "Ask before changes")
        #expect(ask == .askBeforeChanges)

        let edit = AccessLevelPermissionLogic.migrateLegacyAccessLevel(raw: "Edit automatically")
        #expect(edit == .editAutomatically)

        let full = AccessLevelPermissionLogic.migrateLegacyAccessLevel(raw: "Full access")
        #expect(full == .fullAccess)
    }

    @Test("migrateLegacyAccessLevel unknown raw falls back to askBeforeChanges")
    func migrateUnknownRaw() {
        let level = AccessLevelPermissionLogic.migrateLegacyAccessLevel(raw: "Something else")
        #expect(level == .askBeforeChanges)
    }

    @Test("shouldSwitchToPlanAgent returns true for Plan mode")
    func shouldSwitchToPlanAgentTrue() {
        #expect(AccessLevelPermissionLogic.shouldSwitchToPlanAgent(legacyRaw: "Plan mode"))
    }

    @Test("shouldSwitchToPlanAgent returns false for non-plan modes")
    func shouldSwitchToPlanAgentFalse() {
        #expect(!AccessLevelPermissionLogic.shouldSwitchToPlanAgent(legacyRaw: "Ask before changes"))
        #expect(!AccessLevelPermissionLogic.shouldSwitchToPlanAgent(legacyRaw: "Edit automatically"))
        #expect(!AccessLevelPermissionLogic.shouldSwitchToPlanAgent(legacyRaw: "Full access"))
        #expect(!AccessLevelPermissionLogic.shouldSwitchToPlanAgent(legacyRaw: ""))
    }
}
