import XCTest
@testable import myCoder

/// TDD: users can add a custom model to a web provider's model list.
/// The model must appear in allModels after addition, and must
/// survive a save/load cycle (persisted to UserDefaults).
final class CustomModelAdditionTests: XCTestCase {

    func testCustomModelCanBeAddedToProvider() throws {
        // Given: a web provider config with no custom models
        var config = WebProviderConfig(vendor: .custom, acknowledgedToS: true)
        XCTAssertTrue(config.allModels.isEmpty, "Should start with empty models")

        // When: a custom model is added via the public API
        config.addCustomModel("my-custom-model-v1")

        // Then: the model appears in the list
        XCTAssertTrue(config.allModels.contains("my-custom-model-v1"),
                      "Custom model should be in allModels")
    }

    func testCustomModelSurvivesSaveAndLoad() throws {
        // Given: a config with a custom model
        var config = WebProviderConfig(vendor: .custom, acknowledgedToS: true)
        config.addCustomModel("persisted-model-42")
        config.addCustomModel("another-model")

        // When: saved and reloaded
        let providers = [config]
        WebProviderStore.save(providers)
        let loaded = WebProviderStore.load()

        // Then: the custom models are preserved
        let loadedConfig = loaded.first(where: { $0.id == config.id })
        XCTAssertNotNil(loadedConfig, "Config should be reloadable")
        XCTAssertTrue(loadedConfig!.allModels.contains("persisted-model-42"),
                      "Custom model should survive save/load")
        XCTAssertTrue(loadedConfig!.allModels.contains("another-model"),
                      "All custom models should survive save/load")
    }

    func testDuplicateCustomModelIsNotAdded() throws {
        // Given: a config with a custom model
        var config = WebProviderConfig(vendor: .custom, acknowledgedToS: true)
        config.addCustomModel("unique-model")

        // When: the same model is added again
        config.addCustomModel("unique-model")

        // Then: only one copy exists
        let count = config.allModels.filter { $0 == "unique-model" }.count
        XCTAssertEqual(count, 1, "Duplicate custom model should not be added")
    }

    func testEmptyCustomModelIsNotAdded() throws {
        // Given: a config
        var config = WebProviderConfig(vendor: .custom, acknowledgedToS: true)
        let initialCount = config.allModels.count

        // When: an empty model name is added
        config.addCustomModel("")

        // Then: nothing changes
        XCTAssertEqual(config.allModels.count, initialCount,
                       "Empty model name should not be added")
    }
}
