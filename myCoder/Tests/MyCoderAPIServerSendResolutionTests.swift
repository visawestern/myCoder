import Testing
import Foundation
@testable import myCoder

/// Round 29 R4: the af0ef4d SIGSEGV fix moved @Published mutations into a
/// fire-and-forget `DispatchQueue.main.async`, but kept building the HTTP
/// response from values captured BEFORE that block runs — so `/api/send`
/// answered with the STALE chatId/providerId/modelId (for a brand-new chat:
/// empty or the previously selected session). The response must reflect the
/// post-mutation state, so target resolution is extracted into one MainActor
/// function whose result IS what the response reports.
@Suite("Round 29 R4 — API send target resolution matches the response")
struct MyCoderAPIServerSendResolutionTests {

    @MainActor
    @Test("new chat request resolves to the freshly created session id")
    func newChatResolvesToCreatedSession() {
        let appState = AppState()
        let before = appState.sessions.count

        let resolved = MyCoderAPIServer.resolveSendTargets(
            appState: appState, providerId: nil, modelId: nil, chatId: nil)

        #expect(!resolved.chatID.isEmpty, "a created session id must be returned, not \"\"")
        #expect(resolved.chatID == appState.selectedSession?.id,
                "response chatId must equal the selected session")
        #expect(appState.sessions.count == before + 1, "exactly one API Chat session is created")
        #expect(appState.sessions.contains { $0.id == resolved.chatID })
    }

    @MainActor
    @Test("existing chatId selects that session and echoes its id")
    func existingChatSelected() {
        let appState = AppState()
        let session = ChatSession(id: "fixed-chat-id", title: "T",
                                  directory: FileManager.default.temporaryDirectory.path,
                                  branch: nil)
        appState.upsertSession(session)

        let resolved = MyCoderAPIServer.resolveSendTargets(
            appState: appState, providerId: nil, modelId: nil, chatId: "fixed-chat-id")

        #expect(resolved.chatID == "fixed-chat-id")
        #expect(appState.selectedSession?.id == "fixed-chat-id")
        #expect(appState.sessions.count == 1, "no duplicate session may be created")
    }

    @MainActor
    @Test("provider selection is applied before resolution reads it back")
    func selectionAppliedBeforeReadback() {
        let appState = AppState()
        // selectProvider stores the id as-is; selectModel only accepts models
        // known for the provider, so resolution must report the state AFTER
        // applying the request — provider echoed, model left unchanged when
        // the requested one is not available.
        let resolved = MyCoderAPIServer.resolveSendTargets(
            appState: appState, providerId: "web:some-provider", modelId: "k2", chatId: nil)

        #expect(resolved.providerID == "web:some-provider",
                "providerId in the response must be the requested one, got \(resolved.providerID)")
        #expect(appState.selectedProviderID == "web:some-provider")
    }
}
