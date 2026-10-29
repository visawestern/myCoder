import Testing
@testable import myCoder

@Suite("Session Reload Logic")
struct SessionReloadLogicTests {

    @Test("A chat that was already loaded is shown from cache without re-reading history")
    func cachedChatIsNotReloaded() {
        #expect(SessionReloadLogic.shouldReloadMessages(hasCachedMessages: true) == false)
    }

    @Test("A chat without a loaded feed reads its history")
    func uncachedChatIsReloaded() {
        #expect(SessionReloadLogic.shouldReloadMessages(hasCachedMessages: false) == true)
    }

    @Test("A running generation in another chat does not block loading the selected one")
    func backgroundGenerationDoesNotBlockReload() {
        // Regression: the old rule skipped the reload while `appState.isLoading`
        // was true, so switching chats mid-generation kept showing the previous
        // chat's messages. The store now partitions feeds by session and the
        // decision only depends on the selected chat.
        #expect(SessionReloadLogic.shouldReloadMessages(hasCachedMessages: false) == true)
    }
}
