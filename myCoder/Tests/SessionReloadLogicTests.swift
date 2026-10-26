import Testing
@testable import myCoder

@Suite("Session Reload Logic")
struct SessionReloadLogicTests {

    @Test("Skip reload while send is in flight with local messages")
    func skipDuringActiveSend() {
        #expect(
            SessionReloadLogic.shouldReloadMessages(
                newSessionID: "ses_new",
                currentSessionID: nil,
                localMessageCount: 2,
                isLoading: true
            ) == false
        )
    }

    @Test("Skip reload when same session already has local messages")
    func skipSameSessionWithMessages() {
        #expect(
            SessionReloadLogic.shouldReloadMessages(
                newSessionID: "ses_1",
                currentSessionID: "ses_1",
                localMessageCount: 3,
                isLoading: false
            ) == false
        )
    }

    @Test("Reload when switching to a different session")
    func reloadOnSessionSwitch() {
        #expect(
            SessionReloadLogic.shouldReloadMessages(
                newSessionID: "ses_2",
                currentSessionID: "ses_1",
                localMessageCount: 3,
                isLoading: false
            ) == true
        )
    }

    @Test("Reload empty local state for newly selected session")
    func reloadWhenLocalEmpty() {
        #expect(
            SessionReloadLogic.shouldReloadMessages(
                newSessionID: "ses_1",
                currentSessionID: nil,
                localMessageCount: 0,
                isLoading: false
            ) == true
        )
    }
}
