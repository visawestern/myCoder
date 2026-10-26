import Testing
import Foundation
@testable import myCoder

@Suite("Chat Scroll Behavior")
struct ChatScrollBehaviorTests {

    @Test("Session switch forces a scroll to the latest message")
    func sessionSwitchForcesScroll() {
        #expect(ChatScrollLogic.shouldScrollOnSessionChange(oldSessionID: nil, newSessionID: "s1"))
        #expect(ChatScrollLogic.shouldScrollOnSessionChange(oldSessionID: "s1", newSessionID: "s2"))
    }

    @Test("No forced scroll when the session did not actually change")
    func noScrollWithoutChange() {
        #expect(!ChatScrollLogic.shouldScrollOnSessionChange(oldSessionID: "s1", newSessionID: "s1"))
        #expect(!ChatScrollLogic.shouldScrollOnSessionChange(oldSessionID: "s1", newSessionID: nil))
    }

    @Test("Scroll-to-bottom button shows only when scrolled away from the bottom")
    func floatingButtonVisibility() {
        #expect(ChatScrollLogic.showsScrollToBottomButton(isBottomVisible: false, messageCount: 5))
        #expect(!ChatScrollLogic.showsScrollToBottomButton(isBottomVisible: true, messageCount: 5))
    }

    @Test("Scroll-to-bottom button hidden for empty chats")
    func floatingButtonHiddenWhenEmpty() {
        #expect(!ChatScrollLogic.showsScrollToBottomButton(isBottomVisible: false, messageCount: 0))
    }

    @Test("Chat panel renders the floating scroll button and forces scroll on load")
    func chatPanelWiresScrollBehaviors() throws {
        let source = try sourceText("myCoder/Sources/Views/ChatPanelView.swift")
        #expect(source.contains("showsScrollToBottomButton"))
        #expect(source.contains("shouldScrollOnSessionChange"))
        #expect(source.contains("ScrollToBottomButton"))
    }

    private func sourceText(_ relativePath: String) throws -> String {
        try RepoRoot.sourceText(relativePath)
    }
}
