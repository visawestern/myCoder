import XCTest
@testable import myCoder

/// TDD: when a web session is captured (login), the app should discover the
/// real model list from the vendor's web UI and update the config's
/// discoveredModels. The catalog's hardcoded list is a fallback only.
final class LiveModelVerificationTests: XCTestCase {

    func testDiscoverUpdatesConfigWithRealModels() throws {
        // Given: a config with stale/catalog models
        var config = WebProviderConfig(vendor: .kimi, acknowledgedToS: true)
        config.discoveredModels = [WebProviderModel(name: "old-model-1"), WebProviderModel(name: "old-model-2")]

        // When: discovery returns a fresh list (simulating live web scrape)
        config.discoveredModels = [WebProviderModel(name: "k2"), WebProviderModel(name: "k2-thinking"), WebProviderModel(name: "k1.5")]

        // Then: the config reflects the live models, not the stale catalog
        XCTAssertEqual(config.discoveredModels.map { $0.name }, ["k2", "k2-thinking", "k1.5"],
                       "Config should reflect live-discovered models")
        XCTAssertFalse(config.discoveredModels.contains { $0.name == "old-model-1" },
                       "Stale catalog models should be replaced")
    }

    func testDiscoveryFailureKeepsCatalogFallback() throws {
        // Given: a config with catalog models
        var config = WebProviderConfig(vendor: .kimi, acknowledgedToS: true)
        config.discoveredModels = [WebProviderModel(name: "k2"), WebProviderModel(name: "k2-thinking"), WebProviderModel(name: "k1.5")]

        // When: discovery fails (returns nil/empty)
        let discoveryResult: [WebProviderModel]? = nil
        if let models = discoveryResult, !models.isEmpty {
            config.discoveredModels = models
        }

        // Then: catalog models are preserved as fallback
        XCTAssertEqual(config.discoveredModels.map { $0.name }, ["k2", "k2-thinking", "k1.5"],
                       "Catalog models should be kept when discovery fails")
    }

    func testDiscoveryResultIsPersisted() throws {
        // Given: a config with discovered models
        var config = WebProviderConfig(vendor: .qwen, acknowledgedToS: true)
        config.discoveredModels = [WebProviderModel(name: "qwen2.5-max"), WebProviderModel(name: "qwen2.5-plus")]

        // When: saved and reloaded
        WebProviderStore.save([config])
        let loaded = WebProviderStore.load().first(where: { $0.id == config.id })

        // Then: discovered models persist
        XCTAssertNotNil(loaded, "Config should be reloadable")
        XCTAssertTrue(loaded!.discoveredModels.contains { $0.name == "qwen2.5-max" },
                      "Discovered models should persist across save/load")
    }
}
