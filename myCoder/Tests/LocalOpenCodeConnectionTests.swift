import Testing
import Foundation
@testable import myCoder

/// Local OpenCode server connection (user's own `opencode serve`).
/// Proved live 2026-10-13: anonymous Zen is gated (403), random ses_ IDs are
/// gated too — the only working path is the user's authenticated local
/// server (basic auth, session REST API).
@Suite("Local OpenCode server connection (OC-1)")
struct LocalOpenCodeConnectionTests {

    @Test func healthPathIsGlobalHealth() {
        #expect(LocalProviderKind.openCode.healthPath == "/global/health")
        let cfg = LocalProviderConfig(kind: .openCode, host: "127.0.0.1", port: 4096)
        #expect(cfg.healthURL == "http://127.0.0.1:4096/global/health")
    }

    @Test func basicAuthHeaderEncodesCredentials() {
        let header = LocalProviderConfig.basicAuthHeader(username: "opencode", password: "test123")
        #expect(header == "Basic " + Data("opencode:test123".utf8).base64EncodedString())
    }

    @Test func emptyPasswordYieldsNoHeader() {
        #expect(LocalProviderConfig.basicAuthHeader(username: "opencode", password: "") == nil)
        #expect(LocalProviderConfig.basicAuthHeader(username: "", password: "") == nil)
    }

    @Test func passwordNotPersistedInUserDefaultsJSON() throws {
        var cfg = LocalProviderConfig(kind: .openCode, host: "127.0.0.1", port: 4096)
        cfg.username = "opencode"
        let data = try JSONEncoder().encode(cfg)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(!json.contains("password"))
        #expect(!json.contains("test123"))
        let decoded = try JSONDecoder().decode(LocalProviderConfig.self, from: data)
        #expect(decoded == cfg)
    }

    @Test func keychainIdentifierIsStablePerProvider() {
        let cfg = LocalProviderConfig(id: "abc", kind: .openCode)
        #expect(cfg.passwordKeychainIdentifier == "local-provider-password-abc")
    }

    @Test func confirmAppliesCredentialsWithoutPersistingPassword() throws {
        let cfg = LocalProviderConfirmLogic.applyCredentials(
            to: LocalProviderConfig(kind: .openCode, host: "127.0.0.1", port: 4096),
            username: "opencode")
        #expect(cfg.username == "opencode")
        let data = try JSONEncoder().encode(cfg)
        #expect(!(String(data: data, encoding: .utf8) ?? "").contains("password"))
    }

    @Test func detectorForwardsAuthHeaders() async {
        // Headers must reach the probe (locked serve answers 401 without them).
        final class Box: @unchecked Sendable {
            var all: [[String: String]] = []
        }
        let box = Box()
        struct CapProbe: ProviderProbe {
            let box: Box
            func get(url: String, headers: [String : String]) async -> (Int, Data)? {
                box.all.append(headers)
                return nil
            }
        }
        _ = await ProviderAutoDetector.detect(
            host: "127.0.0.1", port: 4096,
            headers: ["Authorization": "Basic eA=="],
            probe: CapProbe(box: box))
        #expect(!box.all.isEmpty)
        #expect(box.all.allSatisfy { $0["Authorization"] == "Basic eA==" })
    }
}
