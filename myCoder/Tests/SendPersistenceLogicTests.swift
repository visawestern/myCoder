import Foundation
import Testing
@testable import myCoder

@Suite("CHAT-18: failed first send persistence")
struct SendPersistenceLogicTests {
    @Test("new project send requires a local session before first append")
    func newProjectRequiresSessionBootstrap() {
        #expect(SendPersistenceLogic.shouldBootstrapSession(selectedSessionID: nil, workspacePath: "/tmp/project"))
        #expect(SendPersistenceLogic.shouldPersistInitialMessages(selectedSessionID: nil, workspacePath: "/tmp/project"))
    }

    @Test("existing session reuses its identity and does not create a duplicate")
    func existingSessionDoesNotBootstrap() {
        let noStoreSession: String? = nil
        #expect(!SendPersistenceLogic.shouldBootstrapSession(selectedSessionID: "session-1", workspacePath: "/tmp/project"))
        #expect(SendPersistenceLogic.sessionIDForInitialAppend(existingStoreSessionID: noStoreSession, selectedSessionID: "session-1", bootstrappedSessionID: "new") == "session-1")
        #expect(SendPersistenceLogic.sessionIDForInitialAppend(existingStoreSessionID: "store-1", selectedSessionID: "session-1", bootstrappedSessionID: "new") == "store-1")
    }

    @Test("no project fails closed instead of writing history into an unrelated database")
    func noProjectCannotPersist() {
        let noSession: String? = nil
        let noPath: String? = nil
        #expect(!SendPersistenceLogic.shouldBootstrapSession(selectedSessionID: noSession, workspacePath: noPath))
        #expect(!SendPersistenceLogic.shouldPersistInitialMessages(selectedSessionID: noSession, workspacePath: noPath))
        #expect(SendPersistenceLogic.sessionIDForInitialAppend(existingStoreSessionID: noSession, selectedSessionID: noSession, bootstrappedSessionID: noSession) == nil)
    }
}
