import Foundation
import Testing
@testable import myCoder

@Suite("STO-27 configuration transfer UX")
struct AppConfigurationTransferLogicTests {
    @Test("global configuration import requires explicit replacement confirmation")
    func importRequiresConfirmation() {
        #expect(AppConfigurationTransferLogic.importRequiresConfirmation)
    }

    @Test("failed export produces a visible failure notice")
    func failedExportIsNotSilent() {
        let notice = AppConfigurationTransferLogic.notice(
            operation: .export,
            succeeded: false
        )
        #expect(notice.outcome == .failure)
        #expect(!notice.title.isEmpty)
        #expect(!notice.message.isEmpty)
    }

    @Test("failed import produces a visible failure notice")
    func failedImportIsNotSilent() {
        let notice = AppConfigurationTransferLogic.notice(
            operation: .import,
            succeeded: false
        )
        #expect(notice.outcome == .failure)
        #expect(!notice.title.isEmpty)
        #expect(!notice.message.isEmpty)
    }
}
