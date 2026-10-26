import Foundation

enum ModelSelectionPresentationLogic {
    static func parameterModelID(selectedModel: String, effectiveModel: String) -> String? {
        let effective = effectiveModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !effective.isEmpty { return effective }
        let selected = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return selected.isEmpty ? nil : selected
    }

    static func displayModel(selectedModel: String, effectiveModel: String) -> String? {
        parameterModelID(selectedModel: selectedModel, effectiveModel: effectiveModel)
    }

    static func isSelected(candidate: String, selectedModel: String, effectiveModel: String) -> Bool {
        candidate == parameterModelID(selectedModel: selectedModel, effectiveModel: effectiveModel)
    }

    static func shouldShowParameters(selectedModel: String, effectiveModel: String) -> Bool {
        parameterModelID(selectedModel: selectedModel, effectiveModel: effectiveModel) != nil
    }
}
