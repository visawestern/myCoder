import Testing
import Foundation
@testable import myCoder

/// `RollbackDialogueLoader`: выбор источника сообщений для отката.
/// Если живой фид (MessageStore) пуст — например, при откате через API для
/// незагруженного чата — сообщения поднимаются из БД.
@MainActor
@Suite("RollbackDialogueLoader")
struct RollbackDialogueLoaderTests {

    private func message(_ id: String) -> Message {
        Message(id: id, role: .user, content: "text-\(id)", isFinished: true)
    }

    @Test("Непустой фид store — берётся store, БД не спрашивается")
    func liveFeedWins() {
        let live = [message("m1"), message("m2")]
        var dbQueries = 0
        let result = RollbackDialogueLoader.resolve(
            for: "chat-1",
            fromStore: { live },
            fromDatabase: { _ in
                dbQueries += 1
                return []
            }
        )
        #expect(result.map(\.id) == ["m1", "m2"])
        #expect(dbQueries == 0)
    }

    @Test("Пустой фид — сообщения грузятся из БД")
    func emptyFeedFallsBackToDatabase() {
        let db = [message("d1"), message("d2"), message("d3")]
        let result = RollbackDialogueLoader.resolve(
            for: "chat-1",
            fromStore: { [] },
            fromDatabase: { sessionID in
                #expect(sessionID == "chat-1")
                return db
            }
        )
        #expect(result.map(\.id) == ["d1", "d2", "d3"])
    }

    @Test("И store пуст, и БД пуста — пустой результат")
    func bothEmpty() {
        let result = RollbackDialogueLoader.resolve(
            for: "chat-1",
            fromStore: { [] },
            fromDatabase: { _ in [] }
        )
        #expect(result.isEmpty)
    }
}
