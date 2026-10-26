import XCTest
@testable import myCoder

/// TDD: draft (unsent) message text must persist per session and survive
/// a session switch. On send, the draft is cleared.
final class DraftPersistenceTests: XCTestCase {

    func testDraftIsSavedWhenTextChanges() throws {
        // Given: a session and some draft text
        let sessionID = "draft-test-session"
        let draftText = "This is my unsent message"

        // When: the draft is saved
        try DatabaseManager.shared.setSessionDraftText(sessionId: sessionID, text: draftText)

        // Then: it can be read back
        let loaded = try DatabaseManager.shared.getSessionDraftText(sessionId: sessionID)
        XCTAssertEqual(loaded, draftText, "Draft should be persisted")
    }

    func testDraftIsClearedOnSend() throws {
        // Given: a session with a draft
        let sessionID = "draft-clear-session"
        try DatabaseManager.shared.setSessionDraftText(sessionId: sessionID, text: "to be cleared")

        // When: the draft is cleared (e.g., on send)
        try DatabaseManager.shared.setSessionDraftText(sessionId: sessionID, text: nil)

        // Then: reading back returns nil
        let loaded = try DatabaseManager.shared.getSessionDraftText(sessionId: sessionID)
        XCTAssertNil(loaded, "Draft should be cleared")
    }

    func testDraftSurvivesSessionSwitch() throws {
        // Given: two sessions with different drafts
        let sessionA = "session-A"
        let sessionB = "session-B"
        try DatabaseManager.shared.setSessionDraftText(sessionId: sessionA, text: "draft A")
        try DatabaseManager.shared.setSessionDraftText(sessionId: sessionB, text: "draft B")

        // When: switching from A to B and back
        let draftB = try DatabaseManager.shared.getSessionDraftText(sessionId: sessionB)
        let draftA = try DatabaseManager.shared.getSessionDraftText(sessionId: sessionA)

        // Then: each session retains its own draft
        XCTAssertEqual(draftA, "draft A", "Session A draft should be preserved")
        XCTAssertEqual(draftB, "draft B", "Session B draft should be preserved")
    }

    func testDraftIsEmptyByDefault() throws {
        // Given: a session that never had a draft
        let sessionID = "fresh-session"

        // When: reading the draft
        let loaded = try DatabaseManager.shared.getSessionDraftText(sessionId: sessionID)

        // Then: it's nil
        XCTAssertNil(loaded, "Fresh session should have no draft")
    }
}
