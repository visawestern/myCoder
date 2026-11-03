import Foundation

/// JSON payload for `POST /api/context-preview`. The built-in API is the
/// project's verification surface (user directive 2026-11-03): a live check
/// must show the same payload the model receives, split into the same tabs the
/// viewer renders — without driving the GUI.
enum ContextPreviewLogic {

    /// Stable names for the API. `String(describing:)` would leak Swift
    /// spelling; these are part of the contract and are tested.
    static func statusName(_ status: SendContextStatus) -> String {
        switch status {
        case .disabled: return "disabled"
        case .projectless: return "projectless"
        case .noEvidence: return "noEvidence"
        case .compiled: return "compiled"
        case .failed: return "failed"
        case .projectlessFirstTurn: return "projectlessFirstTurn"
        case .chatContext: return "chatContext"
        }
    }

    static func payload(message: String,
                        preparation: SendContextPreparation,
                        stages: [ContextStageLogLogic.Stage],
                        systemPrompt: String) -> [String: Any] {
        let pack = preparation.pack
        let auditText = pack?.auditText ?? (systemPrompt.isEmpty ? "" : TurnDelivery.withSystem(systemPrompt, modelText: "## Запрос\n" + message))
        let tabs = TurnPresentation.sections(auditText).map { section in
            ["title": section.title, "body": section.body]
        }
        var payload: [String: Any] = [
            "message": message,
            "status": statusName(preparation.status),
            "summary": SendContextPreparationLogic.summary(preparation),
            "stages": stages.map { ContextStageLogLogic.line(for: $0) },
            "tabs": tabs,
            "auditText": auditText,
            "modelText": preparation.modelText,
            "modelTextBytes": preparation.modelText.utf8.count,
            "systemPromptBytes": systemPrompt.utf8.count,
            "included": pack?.manifest.included ?? [],
            "dropped": (pack?.manifest.dropped ?? []).map { ["path": $0.path, "reason": $0.reason] },
            "unknowns": pack?.unknowns ?? [],
            "memoryCount": pack?.memoryIDs.count ?? 0,
            "estimatedTokens": pack?.estimatedTokens ?? 0
        ]
        if let warning = preparation.warning {
            payload["warning"] = warning
        }
        return payload
    }
}
