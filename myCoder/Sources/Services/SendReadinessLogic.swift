import Foundation

enum SendReadinessLogic {
    /// Проверяет, требуется ли подключение к MiMo Serve или готовность прямого provider route.
    /// Если выбран кастомный провайдер с API-ключом — сервер не обязателен.
    static func connectionValidationError(
        serverConnected: Bool,
        selectedProviderID: String = "",
        autoFreeReady: Bool = true,
        customProviders: [CustomProvider] = [],
        localProviderIDs: [String] = [],
        webProviderIDs: [String] = [],
        serverProviderIDs: [String] = [],
        webConnected: Bool? = nil
    ) -> String? {
        SendProviderReadinessLogic.connectionValidationError(
            serverConnected: serverConnected,
            selectedProviderID: selectedProviderID,
            autoFreeID: MyCoderAutoFreeProvider.builtInID,
            autoFreeReady: autoFreeReady,
            customProviders: customProviders.map {
                SendProviderReadinessLogic.CustomProviderState(
                    id: $0.id,
                    isEnabled: $0.isEnabled,
                    requiresAPIKey: $0.requiresAPIKey,
                    hasAPIKey: !$0.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            },
            localProviderIDs: localProviderIDs,
            webProviderIDs: webProviderIDs,
            serverProviderIDs: serverProviderIDs,
            webConnected: webConnected
        )
    }

    static func sendValidationError(
        modelID: String,
        providerID: String?,
        effectiveModelID: String? = nil
    ) -> String? {
        let trimmedModel = SendProviderReadinessLogic.modelValidationID(
            selectedModel: modelID,
            effectiveModel: effectiveModelID ?? ""
        )
        guard !trimmedModel.isEmpty else {
            return "Select a model before sending."
        }
        guard let providerID,
              !providerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Select a provider for this model."
        }
        return nil
    }

    static func canSendMessage(
        text: String,
        images: [ClipboardImage],
        files: [FileInfo],
        modelID: String,
        providerID: String?,
        serverConnected: Bool = false,
        autoFreeReady: Bool = true,
        customProviders: [CustomProvider] = [],
        localProviderIDs: [String] = [],
        webProviderIDs: [String] = [],
        serverProviderIDs: [String] = [],
        webConnected: Bool? = nil
    ) -> Bool {
        MessageSendValidation.canSend(text: text, images: images, files: files)
            && sendValidationError(modelID: modelID, providerID: providerID) == nil
            && connectionValidationError(
                serverConnected: serverConnected,
                selectedProviderID: providerID ?? "",
                autoFreeReady: autoFreeReady,
                customProviders: customProviders,
                localProviderIDs: localProviderIDs,
                webProviderIDs: webProviderIDs,
                serverProviderIDs: serverProviderIDs,
                webConnected: webConnected
            ) == nil
    }
}

/// Human-readable reason a send is blocked, for showing the user WHY the send
/// button is disabled (Round 8 P1 — the old UI disabled the button silently).
enum SendReadinessReason {
    /// Returns the FIRST blocking condition as an actionable message, or nil
    /// when the send is ready. The UI surfaces this instead of a silent no-op.
    static func reason(
        text: String,
        images: [ClipboardImage],
        files: [FileInfo],
        modelID: String,
        providerID: String?,
        serverConnected: Bool,
        autoFreeReady: Bool = true,
        customProviders: [CustomProvider],
        localProviderIDs: [String],
        webProviderIDs: [String],
        serverProviderIDs: [String] = [],
        webConnected: Bool? = nil,
        effectiveModelID: String? = nil
    ) -> String? {
        // Empty input blocks send with an actionable message (Round 8 P1: the
        // disabled button must explain WHY). Visibility is gated by the UI
        // (InputViews.displayedReason), not by hiding the reason here.
        if !MessageSendValidation.canSend(text: text, images: images, files: files) {
            return "Type a message or attach a file to send."
        }
        if let error = SendReadinessLogic.sendValidationError(
            modelID: modelID,
            providerID: providerID,
            effectiveModelID: effectiveModelID
        ) {
            return error
        }
        return SendReadinessLogic.connectionValidationError(
            serverConnected: serverConnected,
            selectedProviderID: providerID ?? "",
            autoFreeReady: autoFreeReady,
            customProviders: customProviders,
            localProviderIDs: localProviderIDs,
            webProviderIDs: webProviderIDs,
            serverProviderIDs: serverProviderIDs,
            webConnected: webConnected
        )
    }
}
