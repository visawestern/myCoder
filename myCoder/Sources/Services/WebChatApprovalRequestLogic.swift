import Foundation

/// Builds the approval request the web-chat driver shows to the user before a
/// gated tool runs.
enum WebChatApprovalRequestLogic {

    /// Builds one `WebToolApprovalRequest`.
    ///
    /// Destructive shell commands get the full details message (exact command
    /// + risk) and the `isDestructive` flag, so the chat renders the RED card
    /// even at Full access. Out-of-project writes keep their dedicated access
    /// message; every other gated call gets the generic "requires approval"
    /// line.
    ///
    /// Вход: вызов модели, корень проекта, уровень доступа.
    /// Выход: готовый запрос подтверждения.
    /// Зависимости: `WebToolAccessGate`, `WebToolApprovalDetails`,
    /// `OutOfProjectAccessLogic`.
    static func make(
        call: WebToolCall,
        projectRoot: String,
        accessLevel: AccessLevel
    ) -> WebToolApprovalRequest {
        let destructiveReason = WebToolAccessGate.destructiveReason(for: call)
        let message: String
        if destructiveReason != nil {
            message = WebToolApprovalDetails(
                call: call, projectRoot: projectRoot
            ).formattedMessage
        } else {
            message = WebToolAccessGate.outOfProjectPath(
                for: call,
                projectRoot: projectRoot
            ).map {
                OutOfProjectAccessLogic.approvalMessage(
                    tool: call.name,
                    path: $0,
                    projectRoot: projectRoot
                )
            } ?? "\(call.name) requires approval (AccessLevel: \(accessLevel.rawValue))"
        }
        return WebToolApprovalRequest(
            id: UUID().uuidString,
            tool: call.name,
            message: message,
            isDestructive: destructiveReason != nil
        )
    }
}
