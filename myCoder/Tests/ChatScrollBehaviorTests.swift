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

    @Test("Новое сообщение — принудительная прокрутка")
    func newMessageForcesScroll() {
        #expect(ChatScrollLogic.shouldScrollAfterNewMessage(
            oldCount: 1, newCount: 2, oldLastMessageID: "m1", newLastMessageID: "m2"
        ))
        #expect(ChatScrollLogic.shouldScrollAfterNewMessage(
            oldCount: 0, newCount: 1, oldLastMessageID: nil, newLastMessageID: "m1"
        ))
    }

    @Test("Без роста числа сообщений — прокрутка не принудительная")
    func noGrowthNoForcedScroll() {
        #expect(!ChatScrollLogic.shouldScrollAfterNewMessage(
            oldCount: 2, newCount: 2, oldLastMessageID: "m2", newLastMessageID: "m2"
        ))
        #expect(!ChatScrollLogic.shouldScrollAfterNewMessage(
            oldCount: 3, newCount: 2, oldLastMessageID: "m3", newLastMessageID: "m2"
        ))
    }

    @Test("Подгрузка старых сообщений вверх не утягивает вниз")
    func prependingOlderMessagesDoesNotForceScroll() {
        // Количество выросло (2 → 5), но последнее сообщение то же: это
        // пагинация истории, а не новое сообщение.
        #expect(!ChatScrollLogic.shouldScrollAfterNewMessage(
            oldCount: 2, newCount: 5, oldLastMessageID: "m2", newLastMessageID: "m2"
        ))
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
