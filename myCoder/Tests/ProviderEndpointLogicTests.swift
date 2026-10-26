import Foundation
import Testing
@testable import myCoder

@Suite("SET-12: provider endpoint and form defaults")
struct ProviderEndpointLogicTests {
    @Test("normalizes whitespace and trailing slashes once")
    func normalizesBaseURL() {
        #expect(ProviderEndpointLogic.normalizedBaseURL("  https://api.example.com/v1///  ") == "https://api.example.com/v1")
        #expect(ProviderEndpointLogic.modelsURL(for: "https://api.example.com/v1/") == "https://api.example.com/v1/models")
    }

    @Test("rejects missing scheme or host")
    func rejectsInvalidURL() {
        #expect(ProviderEndpointLogic.normalizedBaseURL("api.example.com/v1") == nil)
        #expect(ProviderEndpointLogic.normalizedBaseURL("https://") == nil)
        #expect(ProviderEndpointLogic.modelsURL(for: "not a url") == nil)
    }

    @Test("provider type changes restore the expected API-key default")
    func requiresAPIKeyDefaults() {
        #expect(!ProviderEndpointLogic.defaultRequiresAPIKey(for: .openCodeZen))
        #expect(!ProviderEndpointLogic.defaultRequiresAPIKey(for: .ollama))
        #expect(!ProviderEndpointLogic.defaultRequiresAPIKey(for: .acp))
        #expect(ProviderEndpointLogic.defaultRequiresAPIKey(for: .openAI))
        #expect(ProviderEndpointLogic.defaultRequiresAPIKey(for: .openRouter))
    }
}
