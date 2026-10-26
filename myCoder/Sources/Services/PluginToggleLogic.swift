import Foundation

enum PluginToggleLogic {
    static func toggledDisabledIDs(_ disabledIDs: [String], pluginID: String) -> [String] {
        var result = disabledIDs
        if let index = result.firstIndex(of: pluginID) {
            result.remove(at: index)
        } else {
            result.append(pluginID)
        }
        return result
    }

    static func isEnabled(pluginID: String, disabledIDs: [String]) -> Bool {
        !disabledIDs.contains(pluginID)
    }
}
