import Foundation

/// Which provider and model a chat opens with.
enum SessionModelSelectionLogic {
    struct Selection: Equatable {
        let providerID: String
        let modelID: String
    }

    /// A chat keeps its own model. When it has none yet, the last selection
    /// the user made (kept outside any chat) is used instead.
    static func resolve(
        sessionProviderID: String?,
        sessionModelID: String?,
        preferredProviderID: String?,
        preferredModelID: String?
    ) -> Selection {
        let sessionProvider = trimmed(sessionProviderID)
        if !sessionProvider.isEmpty {
            return Selection(providerID: sessionProvider, modelID: trimmed(sessionModelID))
        }
        return Selection(
            providerID: trimmed(preferredProviderID),
            modelID: trimmed(preferredModelID)
        )
    }

    /// A stored model is applied only when the provider still offers it.
    static func applyableModel(
        _ modelID: String,
        availableModels: [String]
    ) -> String? {
        let model = trimmed(modelID)
        guard !model.isEmpty else { return nil }
        return availableModels.contains(model) ? model : nil
    }

    private static func trimmed(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
