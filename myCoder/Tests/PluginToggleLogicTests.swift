import Foundation
import Testing
@testable import myCoder

@Suite("SET-13: plugin enable/disable settings")
struct PluginToggleLogicTests {
    @Test("toggle adds a plugin to disabled IDs")
    func disable() {
        #expect(PluginToggleLogic.toggledDisabledIDs([], pluginID: "formatter") == ["formatter"])
    }

    @Test("toggle removes an already disabled plugin")
    func enable() {
        #expect(PluginToggleLogic.toggledDisabledIDs(["formatter", "lint"], pluginID: "formatter") == ["lint"])
    }

    @Test("enabled state is false only for the disabled plugin")
    func enabledState() {
        #expect(!PluginToggleLogic.isEnabled(pluginID: "formatter", disabledIDs: ["formatter"]))
        #expect(PluginToggleLogic.isEnabled(pluginID: "lint", disabledIDs: ["formatter"]))
    }
}
