import Testing
import Foundation
@testable import myCoder

/// Описания ошибок: человекочитаемые тексты для каждой ветки LocalizedError
/// в приложении.
@Suite("Описания ошибок (LocalizedError)")
struct ErrorDescriptionTests {

    @Test("AppActionError описывает каждую ветку")
    func appActionErrorDescriptions() {
        #expect(AppActionError.unknownAction("x").errorDescription == "Unknown action: x")
        #expect(AppActionError.missingParameter("p").errorDescription == "Missing parameter: p")
        #expect(AppActionError.invalidParameter("p", "bad").errorDescription == "Invalid parameter p: bad")
        #expect(AppActionError.notFound("chat").errorDescription == "Not found: chat")
        #expect(AppActionError.failed("boom").errorDescription == "boom")
    }

    @Test("KeychainError включает статус-код")
    func keychainErrorDescriptions() {
        #expect(KeychainError.notFound.errorDescription == "Item not found")
        #expect(KeychainError.saveFailed(status: -34018).errorDescription?.contains("-34018") == true)
        #expect(KeychainError.queryFailed(status: 5).errorDescription?.contains("5") == true)
    }

    @Test("SnapshotError и TaskLedgerStoreError")
    func snapshotAndLedgerErrors() {
        #expect(SnapshotError.snapshotNotFound.errorDescription == "Snapshot not found on disk")
        #expect(SnapshotError.invalidMetadata.errorDescription == "Snapshot metadata is corrupted")
        #expect(TaskLedgerStoreError.encodingFailed.errorDescription == "Could not encode the task ledger")
        #expect(TaskLedgerStoreError.noProject.errorDescription == "The task ledger has no project to live in")
    }

    @Test("ExportError: неподдерживаемая версия схемы")
    func exportErrorDescription() {
        #expect(ProjectHistoryExporter.ExportError.unsupportedSchemaVersion(9).errorDescription?.contains("9") == true)
    }

    @Test("DirectChatError и OpenCodeServeError")
    func chatErrors() {
        #expect(DirectChatError.emptyResponse.errorDescription == "The provider returned an empty response. Check the selected model and retry.")
        #expect(DirectChatError.transport("no route").errorDescription?.contains("no route") == true)
        #expect(OpenCodeServeError.unauthorized.errorDescription?.contains("401") == true)
        #expect(OpenCodeServeError.emptyResponse.errorDescription == "The local OpenCode server returned no text.")
    }
}
