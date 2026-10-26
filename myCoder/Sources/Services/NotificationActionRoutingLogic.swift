import Foundation

enum NotificationActionRoutingLogic {
    static let shouldMarkReadBeforeRouting = true

    static func shouldDismissSheet(
        after action: NotificationAction,
        sessionWasFound: Bool
    ) -> Bool {
        switch action {
        case .openSession:
            return sessionWasFound
        case .openSettings, .openGit:
            return true
        case .custom:
            return false
        }
    }
}
