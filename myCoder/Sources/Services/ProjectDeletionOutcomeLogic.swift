import Foundation

enum ProjectDeletionBackupPolicy {
    static func canProceed(
        databaseExists: Bool,
        backupCreated: Bool,
        backupPreserved: Bool
    ) -> Bool {
        !databaseExists || (backupCreated && backupPreserved)
    }
}

enum ProjectDeletionOutcomeLogic {
    enum Outcome: Equatable, Sendable {
        case completed
        case cancelled(completed: Int, total: Int)
        case failed(String)
    }

    enum NoticeOutcome: Equatable {
        case cancelled
        case failed
    }

    struct Notice: Equatable {
        let outcome: NoticeOutcome
        let title: String
        let message: String
    }

    static func shouldRemoveRegistryEntry(_ outcome: Outcome) -> Bool {
        if case .completed = outcome { return true }
        return false
    }

    static func notice(_ outcome: Outcome) -> Notice? {
        switch outcome {
        case .completed:
            return nil
        case let .cancelled(completed, total):
            return Notice(
                outcome: .cancelled,
                title: "Project deletion cancelled",
                message: "The project data was not fully deleted (\(completed) of \(total) items processed). The registry entry was kept."
            )
        case let .failed(reason):
            return Notice(
                outcome: .failed,
                title: "Project deletion failed",
                message: "myCoder kept the registry entry because project data could not be deleted: \(reason)"
            )
        }
    }
}
