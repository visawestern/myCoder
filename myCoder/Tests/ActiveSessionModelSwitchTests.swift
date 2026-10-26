import XCTest
@testable import myCoder

/// TDD: the active web session must allow switching the model and effort
/// without recreating the session. The new values are persisted and used
/// for subsequent messages.
final class ActiveSessionModelSwitchTests: XCTestCase {

    func testCanSwitchModelInActiveSession() throws {
        // Given: an active web session with a selected model
        var config = WebProviderConfig(vendor: .kimi, acknowledgedToS: true)
        config.selectedModel = "k2"
        config.discoveredModels = [WebProviderModel(name: "k2"), WebProviderModel(name: "k2-thinking"), WebProviderModel(name: "k1.5")]

        // When: switching to a different model
        config.selectedModel = "k2-thinking"

        // Then: the selection is updated
        XCTAssertEqual(config.selectedModel, "k2-thinking", "Model should be switched")
        XCTAssertTrue(config.discoveredModels.contains { $0.name == "k2-thinking" },
                      "New model should be in the available list")
    }

    func testCanSwitchEffortInActiveSession() throws {
        // Given: an active session with medium effort
        var config = WebProviderConfig(vendor: .kimi, acknowledgedToS: true)
        config.effort = .medium
        config.discoveredEffortLevels = [.low, .medium, .high]

        // When: switching to high effort
        config.effort = .high

        // Then: the effort is updated
        XCTAssertEqual(config.effort, .high, "Effort should be switched")
    }

    func testSwitchPersistsToStore() throws {
        // Given: a config with a switched model
        var config = WebProviderConfig(vendor: .qwen, acknowledgedToS: true)
        config.selectedModel = "qwen2.5-max"
        config.effort = .high

        // When: saved and reloaded
        WebProviderStore.save([config])
        let loaded = WebProviderStore.load().first(where: { $0.id == config.id })

        // Then: the switched values persist
        XCTAssertNotNil(loaded, "Config should be reloaded")
        XCTAssertEqual(loaded!.selectedModel, "qwen2.5-max", "Switched model should persist")
        XCTAssertEqual(loaded!.effort, .high, "Switched effort should persist")
    }
}
