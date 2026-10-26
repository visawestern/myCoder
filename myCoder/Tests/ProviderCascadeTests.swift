import Testing
import Foundation
@testable import myCoder

@Suite("Provider Cascade")
struct ProviderCascadeTests {

    private func sampleProviders() -> [MimoProviderResponse] {
        [
            MimoProviderResponse(
                id: "mimo",
                name: "MiMo",
                models: [
                    "big-pickle": MimoProviderModel(
                        id: "big-pickle",
                        name: "Big Pickle",
                        status: "active",
                        providerID: "mimo",
                        capabilities: MimoModelCapabilities(reasoning: true, toolcall: true, plan: true),
                        variants: [
                            "low": MimoModelVariant(reasoningEffort: "low"),
                            "medium": MimoModelVariant(reasoningEffort: "medium"),
                            "high": MimoModelVariant(reasoningEffort: "high")
                        ]
                    ),
                    "plain-model": MimoProviderModel(
                        id: "plain-model",
                        name: "Plain",
                        status: "active",
                        providerID: "mimo",
                        capabilities: MimoModelCapabilities(reasoning: false, toolcall: false, plan: false),
                        variants: nil
                    )
                ]
            ),
            MimoProviderResponse(
                id: "openai",
                name: "OpenAI",
                models: [
                    "shared-id": MimoProviderModel(
                        id: "shared-id",
                        name: "Shared",
                        status: "active",
                        providerID: "openai",
                        capabilities: MimoModelCapabilities(reasoning: false, toolcall: true, plan: false),
                        variants: nil
                    )
                ]
            )
        ]
    }

    private func customProvider() -> CustomProvider {
        CustomProvider(
            id: "custom-openai-1",
            name: "Local OpenAI",
            type: .openAI,
            baseURL: "https://api.example.com/v1",
            models: ["gpt-custom", "shared-id"]
        )
    }

    @Test("Provider cascade keeps model when available on new provider")
    func cascadeKeepsModel() {
        let result = ProviderSelectionLogic.cascade(
            to: "mimo",
            currentModelID: "big-pickle",
            currentVariant: "high",
            serverProviders: sampleProviders(),
            customProviders: []
        )
        #expect(result.modelID == "big-pickle")
        #expect(result.variant == "high")
    }

    @Test("Provider cascade resets invalid variant")
    func cascadeResetsVariant() {
        let result = ProviderSelectionLogic.cascade(
            to: "mimo",
            currentModelID: "plain-model",
            currentVariant: "high",
            serverProviders: sampleProviders(),
            customProviders: []
        )
        #expect(result.modelID == "plain-model")
        #expect(result.variant == nil)
    }

    @Test("Provider cascade picks default model when current missing")
    func cascadeDefaultModel() {
        let result = ProviderSelectionLogic.cascade(
            to: "mimo",
            currentModelID: "missing",
            currentVariant: "high",
            serverProviders: sampleProviders(),
            customProviders: []
        )
        #expect(result.modelID == "big-pickle")
    }

    @Test("Resolve provider uses explicit selection for collisions")
    func resolveProviderCollision() {
        let providers = sampleProviders()
        let custom = [customProvider()]
        let explicit = ProviderSettingsLogic.resolveProviderID(
            for: "shared-id",
            selectedProviderID: "openai",
            in: providers,
            customProviders: custom
        )
        #expect(explicit == "openai")

        let customResolved = ProviderSettingsLogic.resolveProviderID(
            for: "shared-id",
            selectedProviderID: "custom-openai-1",
            in: providers,
            customProviders: custom
        )
        #expect(customResolved == "custom-openai-1")
    }

    @Test("Custom provider maps to its id for send")
    func customProviderMapping() {
        let custom = [customProvider()]
        let options = SessionSendLogic.buildSendOptions(
            agentMode: .build,
            selectedVariant: nil,
            modelID: "gpt-custom",
            selectedProviderID: "custom-openai-1",
            providers: [],
            customProviders: custom,
            messageID: "msg_1"
        )
        #expect(options.providerID == "custom-openai-1")
        #expect(options.modelID == "gpt-custom")
        let body = options.requestBody(parts: [["type": "text", "text": "hi"]])
        #expect((body["model"] as? [String: Any])?["providerID"] as? String == "custom-openai-1")
    }

    @Test("Plan agent gate disabled for plain model")
    func planGateDisabled() {
        let providers = sampleProviders()
        #expect(!ProviderCapabilityGates.canSelectPlanAgent(
            modelID: "plain-model",
            providerID: "mimo",
            providers: providers
        ))
        #expect(ProviderCapabilityGates.canSelectPlanAgent(
            modelID: "big-pickle",
            providerID: "mimo",
            providers: providers
        ))
    }

    @Test("Toolcall gate respects explicit false")
    func toolcallGate() {
        let providers = sampleProviders()
        #expect(!ProviderCapabilityGates.canUseTools(
            modelID: "plain-model",
            providerID: "mimo",
            providers: providers
        ))
        #expect(ProviderCapabilityGates.canUseTools(
            modelID: "big-pickle",
            providerID: "mimo",
            providers: providers
        ))
    }

    @Test("Variant menu hidden without reasoning")
    func variantGate() {
        let providers = sampleProviders()
        #expect(!ProviderCapabilityGates.canShowVariantMenu(
            modelID: "plain-model",
            providerID: "mimo",
            providers: providers
        ))
        #expect(ProviderCapabilityGates.canShowVariantMenu(
            modelID: "big-pickle",
            providerID: "mimo",
            providers: providers
        ))
    }

    @Test("Merge models keeps custom entries")
    func mergeModels() {
        let merged = ProviderSettingsLogic.mergeModelIDs(
            serverProviders: sampleProviders(),
            customProviders: [customProvider()]
        )
        #expect(merged.contains("big-pickle"))
        #expect(merged.contains("gpt-custom"))
    }

    @Test("Models scoped to provider")
    func modelsForProvider() {
        let providers = sampleProviders()
        let custom = [customProvider()]
        #expect(ProviderSettingsLogic.models(for: "mimo", in: providers, customProviders: custom) == ["big-pickle", "plain-model"])
        #expect(ProviderSettingsLogic.models(for: "custom-openai-1", in: providers, customProviders: custom) == ["gpt-custom", "shared-id"])
    }

    @Test("Send blocked when provider unresolved")
    func sendBlockedWithoutProvider() {
        #expect(SendReadinessLogic.sendValidationError(modelID: "big-pickle", providerID: nil) != nil)
        #expect(SendReadinessLogic.sendValidationError(modelID: "", providerID: "mimo") != nil)
        #expect(SendReadinessLogic.sendValidationError(modelID: "big-pickle", providerID: "mimo") == nil)
    }

    @Test("Disconnected server reports a visible send error")
    func sendBlockedWithoutServer() {
        #expect(SendReadinessLogic.connectionValidationError(serverConnected: true, selectedProviderID: "mimo", serverProviderIDs: ["mimo"]) == nil)
        #expect(
            SendReadinessLogic.connectionValidationError(serverConnected: false, selectedProviderID: "mimo", serverProviderIDs: ["mimo"])
                == "myCoder Serve is not running or disconnected. Start or reconnect myCoder Serve before sending."
        )
    }

    @Test("Send readiness accepts myCoder Auto Free without MiMo Serve")
    func sendReadinessAcceptsMyCoderAutoFree() {
        #expect(SendReadinessLogic.connectionValidationError(
            serverConnected: false,
            selectedProviderID: MyCoderAutoFreeProvider.builtInID
        ) == nil)
    }

    @Test("Restore providerID from session messages")
    func restoreProviderID() throws {
        let json = """
        [
          {
            "info": {
              "id": "msg_user",
              "role": "user",
              "agent": "build",
              "modelID": "gpt-custom",
              "providerID": "custom-openai-1",
              "variant": "high"
            },
            "parts": [{"type": "text", "text": "hello"}]
          }
        ]
        """.data(using: .utf8)!

        let messages = try JSONDecoder().decode([MimoMessageResponse].self, from: json)
        let selections = SessionSendLogic.restoreSelections(from: messages)
        #expect(selections?.providerID == "custom-openai-1")
        #expect(selections?.modelID == "gpt-custom")
    }

    @Test("MimoModelCapabilities decodes toolcall and plan")
    func capabilitiesDecoding() throws {
        let json = """
        {"reasoning": true, "toolcall": false, "plan": true}
        """.data(using: .utf8)!
        let caps = try JSONDecoder().decode(MimoModelCapabilities.self, from: json)
        #expect(caps.reasoning == true)
        #expect(caps.toolcall == false)
        #expect(caps.plan == true)
    }

    @Test("Agent resources loader returns empty when paths missing")
    func agentResourcesEmpty() {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(AgentResourcesLoader.loadMCPServers(homeDirectory: tempHome).isEmpty)
        #expect(AgentResourcesLoader.loadSkills(homeDirectory: tempHome).isEmpty)
        #expect(AgentResourcesLoader.loadCommands(homeDirectory: tempHome).isEmpty)
    }

    @Test("Plus menu hides tool hooks when tools unavailable")
    func plusMenuGate() {
        let visible = PlusMenuCapabilityLogic.visibleItems(PlusMenuItem.allCases, canUseTools: false)
        #expect(visible == [.addAttachment, .addPhoto])
        #expect(PlusMenuCapabilityLogic.visibleItems(PlusMenuItem.allCases, canUseTools: true).count == PlusMenuItem.allCases.count)
    }
}
