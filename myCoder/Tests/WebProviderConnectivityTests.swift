import Testing
import Foundation
@testable import myCoder

/// Доступность веб-провайдера в селекторе чата. Вход подтверждается живой
/// проверкой страницы AntiBrowser и хранится флагом в конфигурации; файлов
/// cookie больше нет.
@MainActor
@Suite("Web provider connectivity for chat input (plan Раздел 13 п.4)")
struct WebProviderConnectivityTests {

    @Test func notConnectedWhenJustAdded() {
        let cfg = WebProviderConfig(vendor: .kimi, acknowledgedToS: true)
        #expect(!WebProviderConnectivity.isConnected(cfg))
    }

    @Test func connectedAfterConfirmedLoginEvenWithoutToS() {
        var cfg = WebProviderConfig(vendor: .kimi, acknowledgedToS: false)
        cfg.loginConfirmedAt = Date(timeIntervalSince1970: 100)
        #expect(WebProviderConnectivity.isConnected(cfg))
    }

    @Test func providerOptionsOnlyConnected() {
        var connected = WebProviderConfig(vendor: .kimi, acknowledgedToS: true)
        connected.discoveredModels = [WebProviderModel(name: "kimi-real")]
        connected.loginConfirmedAt = Date(timeIntervalSince1970: 100)
        let notConnected = WebProviderConfig(vendor: .qwen, acknowledgedToS: true)
        let opts = WebProviderConnectivity.providerOptions([connected, notConnected])
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
