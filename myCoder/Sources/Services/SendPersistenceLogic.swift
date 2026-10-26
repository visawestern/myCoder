import Foundation

enum SendPersistenceLogic {
    static func shouldBootstrapSession(
        selectedSessionID: String?,
        workspacePath: String?
    ) -> Bool {
        selectedSessionID == nil && hasProjectPath(workspacePath)
    }

    static func shouldPersistInitialMessages(
        selectedSessionID: String?,
        workspacePath: String?
    ) -> Bool {
        selectedSessionID != nil || hasProjectPath(workspacePath)
    }

    static func sessionIDForInitialAppend(
        existingStoreSessionID: String?,
        selectedSessionID: String?,
        bootstrappedSessionID: String?
    ) -> String? {
        existingStoreSessionID ?? selectedSessionID ?? bootstrappedSessionID
    }

    private static func hasProjectPath(_ path: String?) -> Bool {
        guard let path else { return false }
        return !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
