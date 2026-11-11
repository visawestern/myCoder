import Foundation
import Testing
@testable import myCoder

@MainActor
@Suite("WEB-06 real-model provider availability")
struct WebProviderAvailabilityLogicTests {

    @Test("connected provider without real models is not selectable")
    func noRealModelsMeansUnavailable() {
        var config = WebProviderConfig(vendor: .kimi)
        config.loginConfirmedAt = Date(timeIntervalSince1970: 100)
        #expect(WebProviderConnectivity.providerOptions([config]).isEmpty)
    }

    @Test("connected provider with discovered real models is selectable")
    func discoveredModelsMakeProviderAvailable() {
        var config = WebProviderConfig(vendor: .kimi)
        config.discoveredModels = [WebProviderModel(name: "kimi-real")]
        config.loginConfirmedAt = Date(timeIntervalSince1970: 100)
        #expect(WebProviderConnectivity.providerOptions([config]).map(\.id) == ["web:\(config.id)"])
    }
}
