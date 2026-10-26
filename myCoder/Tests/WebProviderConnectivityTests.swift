import Testing
import Foundation
@testable import myCoder

@Suite("Web provider connectivity for chat input (plan Раздел 13 п.4)")
struct WebProviderConnectivityTests {

    private func makeTempHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-webconn-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func persistCookies(_ home: URL, id: String, expiry: TimeInterval,
                                name: String = "kimi-auth") throws {
        let store = WebSessionStore(
            cookies: [BrowserCookie(name: name, value: "v", domain: "d", expiresEpoch: expiry)],
            localStorage: [:], savedAt: Date()
        )
        try WebSessionManager.persist(store, providerId: id, homeDirectory: home)
    }

    @Test func notConnectedWhenJustAdded() throws {
        let home = try makeTempHome()
        let cfg = WebProviderConfig(vendor: .kimi, acknowledgedToS: true)   // no cookies yet
        #expect(!WebProviderConnectivity.isConnected(cfg, homeDirectory: home))
    }

    /// Audit 2026-09-08: analytics/theme cookies captured on a logged-out page
    /// are NOT a login. Regression for the Kimi provider that showed
    /// "connected" with 7 anonymous cookies and no kimi-auth.
    @Test func notConnectedWithAnonymousCookiesOnly() throws {
        let home = try makeTempHome()
        let cfg = WebProviderConfig(vendor: .kimi, acknowledgedToS: true)
        let anonymous = WebSessionStore(
            cookies: [
                BrowserCookie(name: "_ga", value: "v", domain: "d", expiresEpoch: 9_999_999_999),
                BrowserCookie(name: "theme", value: "dark", domain: "d", expiresEpoch: 9_999_999_999),
                BrowserCookie(name: "g_state", value: "{}", domain: "d", expiresEpoch: 9_999_999_999)
            ],
            localStorage: [:], savedAt: Date()
        )
        try WebSessionManager.persist(anonymous, providerId: cfg.id, homeDirectory: home)
        #expect(!WebProviderConnectivity.isConnected(cfg, homeDirectory: home))
    }

    @Test func connectedEvenWithoutToSAcknowledged() throws {
        let home = try makeTempHome()
        let cfg = WebProviderConfig(vendor: .kimi, acknowledgedToS: false)
        try persistCookies(home, id: cfg.id, expiry: 9_999_999_999)
        #expect(WebProviderConnectivity.isConnected(cfg, homeDirectory: home))
    }

    @Test func connectedAfterCookiesAndToS() throws {
        let home = try makeTempHome()
        let cfg = WebProviderConfig(vendor: .kimi, acknowledgedToS: true)
        try persistCookies(home, id: cfg.id, expiry: 9_999_999_999)
        #expect(WebProviderConnectivity.isConnected(cfg, homeDirectory: home))
    }

    @Test func notConnectedWhenCookiesExpired() throws {
        let home = try makeTempHome()
        let cfg = WebProviderConfig(vendor: .kimi, acknowledgedToS: true)
        try persistCookies(home, id: cfg.id, expiry: 100)  // long past
        #expect(!WebProviderConnectivity.isConnected(cfg, homeDirectory: home, now: Date(timeIntervalSince1970: 999_999)))
    }

    @Test func providerOptionsOnlyConnected() throws {
        let home = try makeTempHome()
        var connected = WebProviderConfig(vendor: .kimi, acknowledgedToS: true)
        connected.discoveredModels = [WebProviderModel(name: "kimi-real")]
        let notConnected = WebProviderConfig(vendor: .qwen, acknowledgedToS: true)
        try persistCookies(home, id: connected.id, expiry: 9_999_999_999, name: "kimi-auth")
        let opts = WebProviderConnectivity.providerOptions([connected, notConnected], homeDirectory: home)
        #expect(opts.count == 1)
        #expect(opts.first?.id == "web:\(connected.id)")
        #expect(opts.first?.name.contains("Kimi") == true)
        #expect(opts.first?.isConnected == true)
    }

    @Test func modelsUseDiscoveredWhenPresent() {
        var cfg = WebProviderConfig(vendor: .kimi)
        #expect(WebProviderConnectivity.models(for: cfg).isEmpty)
        cfg.discoveredModels = [WebProviderModel(name: "kimi-real-1"), WebProviderModel(name: "kimi-real-2")]
        #expect(WebProviderConnectivity.models(for: cfg) == ["kimi-real-1", "kimi-real-2"])   // real wins
    }

    @Test func optionIDHelpers() {
        #expect(WebProviderConnectivity.isWebProviderID("web:abc"))
        #expect(!WebProviderConnectivity.isWebProviderID("custom:abc"))
        #expect(WebProviderConnectivity.configID(fromOptionID: "web:abc") == "abc")
        #expect(WebProviderConnectivity.configID(fromOptionID: "other") == nil)
    }
}
