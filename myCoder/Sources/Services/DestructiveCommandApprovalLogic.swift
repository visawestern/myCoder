import Foundation

/// Builds the RED approval card for a destructive shell command on execution
/// paths that do not go through `WebChatApprovalRequestLogic` (the local
/// text-protocol loop of MiMo Serve). One place owns the request shape, so
/// every path shows the same exact command and the same risk text.
enum DestructiveCommandApprovalLogic {

    /// Builds the approval request, or nil when the call is not destructive.
    ///
    /// Вход: вызов модели и корень проекта.
    /// Выход: approval с флагом `isDestructive` или nil.
    /// Зависимости: `WebToolAccessGate`, `WebToolApprovalDetails`.
    static func approval(call: WebToolCall, projectRoot: String) -> PendingToolApproval? {
        guard WebToolAccessGate.destructiveReason(for: call) != nil else { return nil }
        let details = WebToolApprovalDetails(call: call, projectRoot: projectRoot)
        return PendingToolApproval(
            callID: UUID().uuidString,
            tool: call.name,
            message: details.formattedMessage,
            isDestructive: true
        )
    }

    /// Text returned to the model when the user refuses the red card.
    static let denialMessage =
        "user denied permission: the destructive command was not executed. Do not retry it; ask the user how to proceed."
}
