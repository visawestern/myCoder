import Foundation

enum SendAPIResponseLogic {
    static func modelID(selectedModel: String, effectiveModel: String) -> String {
        ModelSelectionPresentationLogic.displayModel(
            selectedModel: selectedModel,
            effectiveModel: effectiveModel
        ) ?? ""
    }
}
