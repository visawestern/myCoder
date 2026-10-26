import Testing
import Foundation
@testable import myCoder

@Suite("Provider auto-detector (plan Раздел 9)")
struct ProviderAutoDetectorTests {

    /// Scriptable probe: maps URL substring -> (status, body). First matching
    /// entry wins; unknown URLs return nil (connection failure).
    private struct ScriptedProbe: ProviderProbe {
        let routes: [(String, Int, Data?)]
        func get(url: String, headers: [String: String]) async -> (Int, Data)? {
            for (path, status, body) in routes where url.contains(path) {
                return (status, body ?? Data())
            }
            return nil
        }
    }

    private func data(_ json: String) -> Data { Data(json.utf8) }

    @Test func detectsOllamaFromTags() async {
        let probe = ScriptedProbe(routes: [
            ("/api/tags", 200, data(#"{"models":[{"name":"llama3"},{"name":"qwen"}]}"#))
        ])
        let info = await ProviderAutoDetector.detect(host: "localhost", port: 11434, probe: probe)
        #expect(info?.kind == .ollama)
        #expect(info?.models == ["llama3", "qwen"])
        #expect(info?.baseURL == "http://localhost:11434")
    }

    @Test func detectsStrataOnDefaultPort() async {
        let probe = ScriptedProbe(routes: [
            ("/v1/models", 200, data(#"{"data":[{"id":"strata-model"}]}"#))
        ])
        let info = await ProviderAutoDetector.detect(host: "127.0.0.1", port: 8399, probe: probe)
        #expect(info?.kind == .strata)
        #expect(info?.models == ["strata-model"])
    }

    @Test func genericOpenAICompatibleOutsideStrataPortIsNotDetected() async {
        let probe = ScriptedProbe(routes: [
            ("/v1/models", 200, data(#"{"data":[{"id":"llama"}]}"#))
        ])
        let info = await ProviderAutoDetector.detect(host: "localhost", port: 1234, probe: probe)
        #expect(info == nil)
    }

    @Test func returnsNilWhenNothingResponds() async {
        let probe = ScriptedProbe(routes: [])
        let info = await ProviderAutoDetector.detect(host: "localhost", port: 9999, probe: probe)
        #expect(info == nil)
    }

    @Test func ollamaProbedBeforeGenericSoItIsNotMisclassified() async {
        // Both /api/tags and /v1/models respond — Ollama must win.
        let probe = ScriptedProbe(routes: [
            ("/api/tags", 200, data(#"{"models":[{"name":"llama3"}]}"#)),
            ("/v1/models", 200, data(#"{"data":[{"id":"other"}]}"#))
        ])
        let info = await ProviderAutoDetector.detect(host: "localhost", port: 11434, probe: probe)
        #expect(info?.kind == .ollama)
        #expect(info?.models == ["llama3"])
    }

    @Test func parseOllamaTagsReturnsNilForEmpty() {
        #expect(ProviderAutoDetector.parseOllamaTags(data(#"{"models":[]}"#)) == nil)
        #expect(ProviderAutoDetector.parseOllamaTags(data("not json")) == nil)
    }

    @Test func parseOpenAIModelsExtractsIds() {
        let ids = ProviderAutoDetector.parseOpenAIModels(data(#"{"data":[{"id":"a"},{"id":"b"}]}"#))
        #expect(ids == ["a", "b"])
        #expect(ProviderAutoDetector.parseOpenAIModels(data(#"{"data":[]}"#)) == nil)
    }

    @Test func isLikelyLocalRecognizesLocalAddresses() {
        #expect(ProviderAutoDetector.isLikelyLocal("localhost"))
        #expect(ProviderAutoDetector.isLikelyLocal("127.0.0.1"))
        #expect(ProviderAutoDetector.isLikelyLocal("192.168.1.10"))
        #expect(ProviderAutoDetector.isLikelyLocal("10.0.0.5"))
        #expect(ProviderAutoDetector.isLikelyLocal("172.16.0.1"))
        #expect(ProviderAutoDetector.isLikelyLocal("myhost.local"))
        #expect(!ProviderAutoDetector.isLikelyLocal("example.com"))
        #expect(!ProviderAutoDetector.isLikelyLocal("8.8.8.8"))
    }

    @Test func detectsOpenCodeServeViaConfigProviders() async {
        // Authenticated `opencode serve`: /global/health is 200 AND
        // /config/providers carries the opencode entry — must win over the
        // generic /v1/models branch.
        let probe = ScriptedProbe(routes: [
            ("/global/health", 200, data(#"{"healthy":true,"version":"1.18.29"}"#)),
            ("/config/providers", 200, data(#"{"providers":[{"id":"opencode","models":{"big-pickle":{"id":"big-pickle"},"muse-spark-1.3-contributor-free":{"id":"muse-spark-1.3-contributor-free"}}},{"id":"google","models":{"gemini-flash-latest":{"id":"gemini-flash-latest"}}}]}"#)),
        ])
        let info = await ProviderAutoDetector.detect(host: "127.0.0.1", port: 4096, headers: ["Authorization": "Basic b3BlbmNvZGU6dGVzdA=="], probe: probe)
        #expect(info?.kind == .openCode)
        #expect(info?.models.contains("big-pickle") == true)
        #expect(info?.models.contains("muse-spark-1.3-contributor-free") == true)
        #expect(info?.models.contains("gemini-flash-latest") == false)
    }

    @Test func lockedServeWithoutAuthDetectsNothing() async {
        // Password-protected serve answers 401 without credentials —
        // must not misclassify as anything (certainly not as sending-ready).
        let probe = ScriptedProbe(routes: [
            ("/global/health", 401, Data()),
            ("/acp/v1/models", 404, Data()),
            ("/v1/models", 404, Data()),
        ])
        let info = await ProviderAutoDetector.detect(host: "127.0.0.1", port: 4096, probe: probe)
        #expect(info == nil)
    }

    @Test func parseOpenCodeProvidersPrefersOpencodeEntry() {
        let providers = ProviderAutoDetector.parseOpenCodeProviders(data(#"{"providers":[{"id":"opencode","models":{"big-pickle":{"id":"big-pickle"}}},{"id":"other","models":{"x":{"id":"x"}}}]}"#))
        #expect(providers == ["big-pickle"])
    }

    @Test func parseOpenCodeProvidersHonorsCustomServerProviderID() {
        let payload = data(#"{"providers":[{"id":"opencode","models":{"big-pickle":{"id":"big-pickle"}}},{"id":"ollama-gemma-cloud","models":{"gemma4:31b-cloud":{"id":"gemma4:31b-cloud"}}}]}"#)
        #expect(ProviderAutoDetector.parseOpenCodeProviders(payload, providerID: "ollama-gemma-cloud") == ["gemma4:31b-cloud"])
        #expect(ProviderAutoDetector.parseOpenCodeProviders(payload, providerID: "missing") == nil)
    }

    @Test func parseOpenCodeProvidersFallsBackToAllKeys() {
        let providers = ProviderAutoDetector.parseOpenCodeProviders(data(#"{"providers":[{"id":"google","models":{"gemini-flash-latest":{"id":"a"}}}]}"#))
        #expect(providers == ["gemini-flash-latest"])
    }

    @Test func parseOpenCodeProvidersRejectsGarbage() {
        #expect(ProviderAutoDetector.parseOpenCodeProviders(data(#"{"nope":[]}"#)) == nil)
        #expect(ProviderAutoDetector.parseOpenCodeProviders(Data()) == nil)
    }
}
