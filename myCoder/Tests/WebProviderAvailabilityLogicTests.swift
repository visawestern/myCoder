import Foundation
import Testing
@testable import myCoder

@Suite("WEB-06 real-model provider availability")
struct WebProviderAvailabilityLogicTests {
    private func makeTempHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mycoder-web-availability-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func persistCookies(_ home: URL, id: String) throws {
        // Audit 2026-09-08: connectivity requires a vendor auth cookie; a
        // bare "sid" is not a login (anonymous cookies regression).
        let store = WebSessionStore(
            cookies: [BrowserCookie(name: "kimi-auth", value: "v", domain: "d", expiresEpoch: 9_999_999_999)],
            localStorage: [:], savedAt: Date()
        )
        try WebSessionManager.persist(store, providerId: id, homeDirectory: home)
    }

    @Test("connected provider without real models is not selectable")
    func noRealModelsMeansUnavailable() throws {
        let home = try makeTempHome()
        let config = WebProviderConfig(vendor: .kimi)
        try persistCookies(home, id: config.id)
        #expect(WebProviderConnectivity.providerOptions([config], homeDirectory: home).isEmpty)
    }

    @Test("connected provider with discovered real models is selectable")
    func discoveredModelsMakeProviderAvailable() throws {
        let home = try makeTempHome()
        var config = WebProviderConfig(vendor: .kimi)
        config.discoveredModels = [WebProviderModel(name: "kimi-real")]
        try persistCookies(home, id: config.id)
        #expect(WebProviderConnectivity.providerOptions([config], homeDirectory: home).map(\.id) == ["web:\(config.id)"])
    }
}
