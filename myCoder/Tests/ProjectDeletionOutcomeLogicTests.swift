import Foundation
import Testing
@testable import myCoder

@Suite("STO-28 deletion outcome safety")
struct ProjectDeletionOutcomeLogicTests {
    @Test("only a completed deletion may remove the registry entry")
    func registryMutationRequiresCompletion() {
        #expect(ProjectDeletionOutcomeLogic.shouldRemoveRegistryEntry(.completed))
        #expect(!ProjectDeletionOutcomeLogic.shouldRemoveRegistryEntry(.cancelled(completed: 2, total: 5)))
        #expect(!ProjectDeletionOutcomeLogic.shouldRemoveRegistryEntry(.failed("permission denied")))
    }

    @Test("cancelled deletion exposes a visible notice")
    func cancellationNoticeIsVisible() throws {
        let notice = try #require(ProjectDeletionOutcomeLogic.notice(
            .cancelled(completed: 2, total: 5)
        ))
        #expect(notice.outcome == .cancelled)
        #expect(!notice.title.isEmpty)
        #expect(!notice.message.isEmpty)
    }

    @Test("failed deletion exposes a visible notice")
    func failureNoticeIsVisible() throws {
        let notice = try #require(ProjectDeletionOutcomeLogic.notice(.failed("permission denied")))
        #expect(notice.outcome == .failed)
        #expect(!notice.title.isEmpty)
        #expect(!notice.message.isEmpty)
    }

    @Test("deletion requires backup and preservation when a database exists")
    func backupFailureBlocksDeletion() {
        #expect(ProjectDeletionBackupPolicy.canProceed(
            databaseExists: true,
            backupCreated: true,
            backupPreserved: true
        ))
        #expect(!ProjectDeletionBackupPolicy.canProceed(
            databaseExists: true,
            backupCreated: false,
            backupPreserved: false
        ))
        #expect(!ProjectDeletionBackupPolicy.canProceed(
            databaseExists: true,
            backupCreated: true,
            backupPreserved: false
        ))
        #expect(ProjectDeletionBackupPolicy.canProceed(
            databaseExists: false,
            backupCreated: false,
            backupPreserved: false
        ))
    }
}
