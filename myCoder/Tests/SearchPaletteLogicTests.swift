import Foundation
import Testing
@testable import myCoder

@Suite("Search palette")
struct SearchPaletteLogicTests {
    private let sessions = [
        ChatSession(id: "1", title: "img-probe"),
        ChatSession(id: "2", title: "что на картинке"),
        ChatSession(id: "3", title: "textfile")
    ]

    @Test func emptyQueryReturnsAllSessions() {
        let result = SearchPaletteLogic.matchingSessions(sessions, query: "")
        #expect(result.count == 3)
    }

    @Test func queryFiltersByTitleCaseInsensitive() {
        let result = SearchPaletteLogic.matchingSessions(sessions, query: "карт")
        #expect(result.count == 1)
        #expect(result[0].title == "что на картинке")
    }

    @Test func queryWithNoMatchesReturnsEmpty() {
        let result = SearchPaletteLogic.matchingSessions(sessions, query: "missing-task")
        #expect(result.isEmpty)
    }
}
