import Foundation

enum StatusBarModelLogic {
    static func displayModel(selectedModel: String, effectiveModel: String) -> String? {
        let effective = effectiveModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !effective.isEmpty { return effective }
        let selected = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return selected.isEmpty ? nil : selected
    }
}
