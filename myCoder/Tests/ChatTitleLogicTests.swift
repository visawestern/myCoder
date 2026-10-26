import Testing
import Foundation
@testable import myCoder

/// Standalone/API chats were all titled "New Chat"/"API Chat" — a wall of
/// identical rows the user can't tell apart (part of "chats get lost").
/// Titles derive from the request's first words: instant, offline, zero
/// tokens. A local generative model can refine later; the heuristic is the
/// floor that always works.
@Suite("Chat titles from request text")
struct ChatTitleLogicTests {

    @Test func firstWordsBecomeTitle() {
        #expect(ChatTitleLogic.title(for: "how do I parse JSON in Swift") == "how do I parse JSON in Swift")
    }

    @Test func longRequestsTrimmedAtWordBoundary() {
        let title = ChatTitleLogic.title(
            for: "please explain how the harness tax affects token consumption in great detail and depth")
        #expect(title.count <= 64)
        #expect(!title.hasSuffix(" "))
        #expect(title.hasPrefix("please explain how the harness"))
    }

    @Test func newlinesCollapse() {
        #expect(ChatTitleLogic.title(for: "fix bug\nin login\nscreen") == "fix bug in login screen")
    }

    @Test func commandPrefixesStripped() {
        #expect(ChatTitleLogic.title(for: "/goal refactor networking layer") == "goal refactor networking layer")
        #expect(ChatTitleLogic.title(for: "?why is this slow") == "why is this slow")
    }

    @Test func emptyFallsBack() {
        #expect(ChatTitleLogic.title(for: "") == "New Chat")
        #expect(ChatTitleLogic.title(for: "   \n  ") == "New Chat")
    }

    @Test func duplicatesNumbered() {
        #expect(ChatTitleLogic.title(for: "fix bug", existingTitles: ["fix bug"]) == "fix bug 2")
        #expect(ChatTitleLogic.title(for: "fix bug", existingTitles: ["fix bug", "fix bug 2"]) == "fix bug 3")
    }

    @Test func russianTextKeptAsIs() {
        #expect(ChatTitleLogic.title(for: "расскажи про образы макос") == "расскажи про образы макос")
    }
}
