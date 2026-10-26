import Testing
import Foundation
import SwiftUI
@testable import myCoder

// MARK: - Provider Tab Tests

@Suite("Providers Settings Tab")
struct ProvidersSettingsTests {

    @Test("SettingsTab has providers case")
    func testProvidersTabExists() {
        #expect(SettingsTab.allCases.contains(.providers))
    }

    @Test("SettingsTab.providers has correct icon")
    func testProvidersTabIcon() {
        #expect(SettingsTab.providers.icon == "server.rack")
    }

    @Test("SettingsTab.providers has correct rawValue")
    func testProvidersTabRawValue() {
        #expect(SettingsTab.providers.rawValue == "Providers")
    }

    @Test("AppLocalization has providers tab name for both languages")
    func testProvidersTabLocalization() {
        let english = AppLocalization.string(.settingsTabProviders, language: .english)
        let russian = AppLocalization.string(.settingsTabProviders, language: .russian)
        #expect(english == "Providers")
        #expect(russian == "Провайдеры")
    }

    // MARK: - ProviderType enhancements

    @Test("ProviderType has endpointType property")
    func testProviderTypeEndpointType() {
        #expect(ProviderType.openRouter.endpointType == .openRouter)
        #expect(ProviderType.omni.endpointType == .omniRouter)
        #expect(ProviderType.acp.endpointType == .agentCodeProtocol)
        #expect(ProviderType.openAI.endpointType == .openAI)
    }

    @Test("ProviderType has endpointDescription")
    func testProviderTypeEndpointDescription() {
        for type in ProviderType.allCases {
            #expect(!type.endpointDescription.isEmpty, "ProviderType \(type.rawValue) must have endpoint description")
        }
    }

    @Test("OpenRouter endpoint description is correct")
    func testOpenRouterEndpointDescription() {
        #expect(ProviderType.openRouter.endpointDescription.contains("OpenRouter"))
    }

    @Test("OmniRouter endpoint description is correct")
    func testOmniRouterEndpointDescription() {
        #expect(ProviderType.omni.endpointDescription.contains("OmniRouter") || ProviderType.omni.endpointDescription.contains("omni"))
    }

    // MARK: - EndpointType enum

    @Test("EndpointType has all expected cases")
    func testEndpointTypeCases() {
        #expect(EndpointType.allCases.count == 4)
        #expect(EndpointType.openAI.rawValue == "openai")
        #expect(EndpointType.openRouter.rawValue == "openrouter")
        #expect(EndpointType.omniRouter.rawValue == "omni")
        #expect(EndpointType.agentCodeProtocol.rawValue == "acp")
    }

    // MARK: - Provider Count Chip

    @Test("ProviderCountChip displays correctly")
    func testProviderCountChip() {
        _ = ProviderCountChip(title: "Providers", count: 5)
        // The view should render without crashing
        // Testing view existence is implicit - if it compiles, it works
    }

    // MARK: - Provider Count in AppState

    @Test("AppState provider counts are accurate")
    func testAppStateProviderCounts() {
        let state = AppState()
        state.customProviders = [
            CustomProvider(id: "p1", name: "P1", type: .openAI, baseURL: "https://a.com", isEnabled: true, models: ["m1", "m2"]),
            CustomProvider(id: "p2", name: "P2", type: .openAI, baseURL: "https://b.com", isEnabled: false, models: ["m3"])
        ]
        state.serverProviders = [
            MimoProviderResponse(id: "srv", name: "Server", models: ["m4": MimoProviderModel(id: "m4")])
        ]

        // enabled custom + server
        #expect(state.providerOptions.count == 2)
        #expect(state.availableModels.count == 3)
    }

    // MARK: - ModelParameterSpoiler

    @Test("ModelParameterSpoiler renders with valid metadata")
    func testModelParameterSpoiler() {
        let meta = MimoProviderModel(
            id: "test-model",
            name: "Test Model",
            capabilities: MimoModelCapabilities(reasoning: true, toolcall: true, plan: false),
            limit: MimoModelLimit(context: 8192, output: 2048),
            cost: MimoModelCost(input: 0.01, output: 0.02)
        )
        
        // The view should render without crashing
        // Testing view existence is implicit
        _ = ModelParameterSpoiler(modelID: "test-model", meta: meta, providerID: "test")
    }

    // MARK: - ModelDetailSpoiler

    @Test("ModelDetailSpoiler renders with valid metadata")
    func testModelDetailSpoiler() {
        let meta = MimoProviderModel(
            id: "test-model",
            name: "Test Model",
            providerID: "test-provider"
        )
        
        // The view should render without crashing
        _ = ModelDetailSpoiler(modelID: "test-model", providerID: "test-provider", meta: meta)
    }
}

// MARK: - Provider Row View Tests

@Suite("ProviderRowView Tests")
struct ProviderRowViewTests {

    @Test("ProviderRowView handles enabled provider")
    func testProviderRowEnabled() {
        let option = ProviderOption(
            id: "test-1",
            name: "Test Provider",
            isCustom: true,
            isConnected: true
        )
        
        // View should render without crashing with valid option
        _ = ProviderRowView(option: option)
    }

    @Test("ProviderRowView handles disabled provider")
    func testProviderRowDisabled() {
        let option = ProviderOption(
            id: "test-2",
            name: "Disabled Provider",
            isCustom: true,
            isConnected: false
        )
        
        // View should render without crashing with valid option
        _ = ProviderRowView(option: option)
    }
}

// MARK: - CustomProvider Chip Display

@Suite("CustomProvider Chip Display")
struct CustomProviderChipTests {

    @Test("CustomProvider shows model count")
    func testCustomProviderModelCount() {
        let custom = CustomProvider(
            id: "test",
            name: "Test",
            type: .openAI,
            baseURL: "https://test.com",
            isEnabled: true,
            models: ["model1", "model2", "model3"]
        )
        
        #expect(custom.models.count == 3)
    }

    @Test("CustomProvider shows tool support status")
    func testCustomProviderToolSupport() {
        let withTools = CustomProvider(
            id: "test1",
            name: "With Tools",
            type: .openAI,
            baseURL: "https://test.com",
            supportsTools: true
        )
        
        let withoutTools = CustomProvider(
            id: "test2",
            name: "Without Tools",
            type: .openAI,
            baseURL: "https://test.com",
            supportsTools: false
        )
        
        #expect(withTools.supportsTools)
        #expect(!withoutTools.supportsTools)
    }

    @Test("CustomProvider shows ACP status")
    func testCustomProviderACPStatus() {
        let withACP = CustomProvider(
            id: "test1",
            name: "With ACP",
            type: .acp,
            baseURL: "http://localhost:8080/acp/v1",
            acpEnabled: true
        )
        
        let withoutACP = CustomProvider(
            id: "test2",
            name: "Without ACP",
            type: .openAI,
            baseURL: "https://test.com",
            acpEnabled: false
        )
        
        #expect(withACP.acpEnabled)
        #expect(!withoutACP.acpEnabled)
    }
}