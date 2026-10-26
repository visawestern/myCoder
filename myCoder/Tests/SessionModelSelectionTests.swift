import Testing
import Foundation
@testable import myCoder

@Suite("Per-chat model selection")
struct SessionModelSelectionTests {

    @Test("A chat with its own provider and model keeps both")
    func sessionSelectionWins() {
        let selection = SessionModelSelectionLogic.resolve(
            sessionProviderID: "provider-a",
            sessionModelID: "model-a",
            preferredProviderID: "provider-b",
            preferredModelID: "model-b"
        )
        #expect(selection == SessionModelSelectionLogic.Selection(providerID: "provider-a", modelID: "model-a"))
    }

    @Test("A chat without a selection falls back to the last used model")
    func fallsBackToPreferredSelection() {
        let selection = SessionModelSelectionLogic.resolve(
            sessionProviderID: nil,
            sessionModelID: nil,
            preferredProviderID: "provider-b",
            preferredModelID: "model-b"
        )
        #expect(selection == SessionModelSelectionLogic.Selection(providerID: "provider-b", modelID: "model-b"))
    }

    @Test("Blank stored values are treated as missing")
    func blankValuesAreMissing() {
        let selection = SessionModelSelectionLogic.resolve(
            sessionProviderID: "  ",
            sessionModelID: "",
            preferredProviderID: "provider-b",
            preferredModelID: "model-b"
        )
        #expect(selection == SessionModelSelectionLogic.Selection(providerID: "provider-b", modelID: "model-b"))
    }

    @Test("A stored model is applied only when the provider still offers it")
    func applyableModelChecksAvailability() {
        #expect(SessionModelSelectionLogic.applyableModel("model-a", availableModels: ["model-a"]) == "model-a")
        #expect(SessionModelSelectionLogic.applyableModel("model-z", availableModels: ["model-a"]) == nil)
        #expect(SessionModelSelectionLogic.applyableModel("", availableModels: ["model-a"]) == nil)
    }

    @Test("The chat stores the model and provider it used")
    func sessionStoresModelAndProvider() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mycoder-session-model-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let manager = try ProjectDatabaseManager.manager(forProjectPath: dir.path)
        defer { ProjectDatabaseManager.evictProject(projectPath: dir.path) }

        try manager.insertSession(
            id: "session-1",
            title: "Chat",
            directory: dir.path,
            modelId: "model-a",
            providerId: "provider-a"
        )

        let stored = try manager.getAllSessions(includeArchived: false)
        #expect(stored.count == 1)
        #expect(stored[0].modelId == "model-a")
        #expect(stored[0].providerId == "provider-a")

        let updated = try manager.updateSessionModel(
            id: "session-1",
            modelId: "model-b",
            providerId: "provider-b"
        )
        #expect(updated == 1)

        let afterUpdate = try manager.getAllSessions(includeArchived: false)
        #expect(afterUpdate[0].modelId == "model-b")
        #expect(afterUpdate[0].providerId == "provider-b")
    }
}
