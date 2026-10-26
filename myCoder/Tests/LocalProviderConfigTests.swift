import Testing
import Foundation
@testable import myCoder

@Suite("Local provider config + unified providers logic (plan Раздел 1)")
struct LocalProviderConfigTests {

    @Test func kindDefaults() {
        #expect(LocalProviderKind.ollama.defaultPort == 11434)
        #expect(LocalProviderKind.localAgent.defaultPort == 4096)
        #expect(LocalProviderKind.ollama.healthPath == "/api/tags")
        #expect(LocalProviderKind.localAgent.healthPath == "/global/health")
    }

    @Test func configUsesKindDefaults() {
        // Every local provider is reached over HTTP only — no CLI, no exec path.
        let ollama = LocalProviderConfig(kind: .ollama)
        #expect(ollama.port == 11434)
        #expect(ollama.serveBaseURL == "http://127.0.0.1:11434")
        #expect(ollama.healthURL == "http://127.0.0.1:11434/api/tags")

        let agent = LocalProviderConfig(kind: .localAgent)
        #expect(agent.port == 4096)
        #expect(agent.healthURL == "http://127.0.0.1:4096/global/health")
    }

    @Test func localAgentUsesNeutralNameNoBranding() {
        let agent = LocalProviderConfig(kind: .localAgent)
        #expect(agent.displayName == "Local Agent")
        #expect(!agent.displayName.contains("MiMo"))
    }

    @Test func customLocalNameOverridesKindName() {
        let custom = LocalProviderConfig(kind: .ollama, name: "Home Ollama")
        #expect(custom.displayName == "Home Ollama")
        #expect(LocalProviderConfig(kind: .ollama, name: "   ").displayName == "Ollama")
    }

    @Test func persistenceRoundTrip() {
        let defaults = UserDefaults(suiteName: "test-local-providers-\(UUID().uuidString)")!
        let providers = [LocalProviderConfig(kind: .ollama), LocalProviderConfig(kind: .localAgent)]
        LocalProviderLogic.save(providers, defaults: defaults)
        let loaded = LocalProviderLogic.load(defaults: defaults)
        #expect(loaded.count == 2)
        #expect(loaded.contains { $0.kind == .ollama })
        #expect(loaded.contains { $0.kind == .localAgent })
    }

    @Test func providerOptionsIncludeOnlyEnabledLocals() {
        let providers = [
            LocalProviderConfig(kind: .ollama, isEnabled: true),
            LocalProviderConfig(kind: .openCode, isEnabled: false)
        ]
        let options = LocalProviderLogic.providerOptions(from: providers)
        #expect(options.count == 1)
        #expect(options.first?.name == "Ollama")
        #expect(options.first?.isCustom == true)
    }

    @Test func configRoundTripsThroughCodable() throws {
        let cfg = LocalProviderConfig(kind: .openCode, port: 5000, openCodeProviderID: "ollama-gemma-cloud")
        let data = try JSONEncoder().encode(cfg)
        let decoded = try JSONDecoder().decode(LocalProviderConfig.self, from: data)
        #expect(decoded == cfg)
        #expect(decoded.openCodeProviderID == "ollama-gemma-cloud")
    }

    @Test func legacyConfigDefaultsToBuiltInOpenCodeProvider() throws {
        let json = #"{"id":"old","kind":"openCode","host":"127.0.0.1","port":4096,"isEnabled":true,"models":["m"],"username":""}"#
        let decoded = try JSONDecoder().decode(LocalProviderConfig.self, from: json.data(using: .utf8)!)
        #expect(decoded.openCodeProviderID == "opencode")
        #expect(decoded.name == nil)
    }

    @Test func refreshReconcileKeepsValidSelection() {
        #expect(LocalModelRefreshLogic.reconcile(current: "big-pickle", fresh: ["big-pickle", "x-free"]) == "big-pickle")
    }

    @Test func refreshReconcileFallsBackToFirst() {
        #expect(LocalModelRefreshLogic.reconcile(current: "gone", fresh: ["a-free", "b-free"]) == "a-free")
    }

    @Test func refreshReconcileNeverWipesOnFailure() {
        #expect(LocalModelRefreshLogic.reconcile(current: "big-pickle", fresh: []) == "big-pickle")
        #expect(LocalModelRefreshLogic.reconcile(current: "", fresh: []) == "")
    }

    @Test func refreshReconcileFillsEmptySelection() {
        #expect(LocalModelRefreshLogic.reconcile(current: "", fresh: ["a-free"]) == "a-free")
    }

    @Test func livePayloadYieldsOnlyFreeModels() {
        // Shape captured live from `opencode serve` /config/providers
        // 2026-10-15: the "opencode" entry must win so the picker shows
        // only models that need no extra provider keys (free filter).
        let payload = """
        {"providers":[
          {"id":"google","models":{"gemini-flash-latest":{}}},
          {"id":"opencode","models":{
            "big-pickle":{},"cat-jam-free":{},"space-bunny-free":{},
            "mimo-v2.6-flash-free":{},"nemotron-3-ultra-free":{},
            "nemotron-3.5-lightning-free":{},
            "muse-spark-1.3-contributor-free":{},
            "longcat-2.5-preview-free":{},"step-5-preview-free":{}}}
        ]}
        """
        let data = payload.data(using: .utf8)!
        let models = ProviderAutoDetector.parseOpenCodeProviders(data)
        #expect(models?.count == 9)
        #expect(models?.allSatisfy { $0 == "big-pickle" || $0.hasSuffix("-free") } == true)
    }
}
