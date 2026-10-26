import Foundation

enum LocalModelSelectionLogic {
    static func isSelected(
        _ model: String,
        selectedProviderID: String,
        activeProviderID: String,
        selectedModel: String?
    ) -> Bool {
        selectedProviderID == activeProviderID && selectedModel == model
    }

    static func modelAfterTap(
        _ model: String,
        catalog: [String],
        current: String?
    ) -> String? {
        catalog.contains(model) ? model : current
    }

    static func shouldSwitchProvider(activeProviderID: String, tappedProviderID: String) -> Bool {
        activeProviderID != tappedProviderID
    }
}
