import Testing
@testable import myCoder

@Suite("Activity 14 provider send readiness")
struct SendProviderReadinessLogicTests {
    @Test("Serve connectivity cannot approve an unrelated expired web route")
    func serveDoesNotMasqueradeAsWebReadiness() {
        let error = SendProviderReadinessLogic.connectionValidationError(
            serverConnected: true,
            selectedProviderID: "web:qwen",
            autoFreeReady: true,
            customProviders: [],
            localProviderIDs: [],
            webProviderIDs: ["qwen"],
            serverProviderIDs: ["serve:gpt"],
            webConnected: false
        )
        #expect(error?.contains("web provider") == true)
    }

    @Test("connected web route is ready without Serve")
    func connectedWebRouteDoesNotNeedServe() {
        #expect(SendProviderReadinessLogic.connectionValidationError(
            serverConnected: false,
            selectedProviderID: "web:qwen",
            autoFreeReady: true,
            customProviders: [],
            localProviderIDs: [],
            webProviderIDs: ["qwen"],
            serverProviderIDs: [],
            webConnected: true
        ) == nil)
    }

    @Test("disconnected known Serve provider names Serve in the actionable error")
    func disconnectedServeProviderIsExplicit() {
        let error = SendProviderReadinessLogic.connectionValidationError(
            serverConnected: false,
            selectedProviderID: "serve:gpt",
            autoFreeReady: true,
            customProviders: [],
            localProviderIDs: [],
            webProviderIDs: [],
            serverProviderIDs: ["serve:gpt"],
            webConnected: nil
        )
        #expect(error?.localizedCaseInsensitiveContains("Serve") == true)
        #expect(error?.localizedCaseInsensitiveContains("connect") == true)
    }

    @Test("effective web model satisfies model preflight when legacy selection is empty")
    func effectiveModelSatisfiesPreflight() {
        #expect(SendProviderReadinessLogic.modelValidationID(
            selectedModel: "",
            effectiveModel: "qwen-max"
        ) == "qwen-max")
        #expect(SendProviderReadinessLogic.modelValidationID(
            selectedModel: "local-model",
            effectiveModel: ""
        ) == "local-model")
    }
}
