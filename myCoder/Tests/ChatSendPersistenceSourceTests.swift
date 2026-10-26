import Foundation
import Testing
@testable import myCoder

@Suite("CHAT-18: send persistence source contract")
struct ChatSendPersistenceSourceTests {
    @Test("session preparation precedes first user-message append")
    func preparationPrecedesAppend() throws {
        let source = try RepoRoot.sourceText("myCoder/Sources/Views/ChatPanelView.swift")
        let preparation = try #require(source.range(of: "let preparedSessionID: String?"))
        let append = try #require(source.range(of: "messageStore.append(userMessage)"))
        #expect(preparation.lowerBound < append.lowerBound)
    }

    @Test("rejected sends use the explicit persistence helper")
    func rejectedSendUsesHelper() throws {
        let source = try RepoRoot.sourceText("myCoder/Sources/Views/ChatPanelView.swift")
        #expect(source.contains("private func recordRejectedSend"))
        #expect(source.contains("self.recordRejectedSend(text: text, files: files, images: images, error: error)"))
    }

    @Test("AppState bootstrap writes to the project database and does not select early")
    func bootstrapUsesProjectDatabase() throws {
        let appSource = try RepoRoot.sourceText("myCoder/Sources/App/MyCoderApp.swift")
        #expect(appSource.contains("func prepareLocalSessionForSend(title: String) -> String?"))
        #expect(appSource.contains("DatabaseBridge.shared.createSession("))
        #expect(appSource.contains("return sessionID"))
    }
}
