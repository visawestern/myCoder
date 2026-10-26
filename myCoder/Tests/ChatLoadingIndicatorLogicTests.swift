import Testing
@testable import myCoder

struct ChatLoadingIndicatorLogicTests {

    @Test("Hidden when no load is in flight")
    func hiddenWhenIdle() {
        #expect(ChatLoadingIndicatorLogic.presentation(isLoading: false, messageCount: 0) == .hidden)
        #expect(ChatLoadingIndicatorLogic.presentation(isLoading: false, messageCount: 12) == .hidden)
    }

    @Test("Centered while an empty chat loads")
    func centeredForInitialLoad() {
        #expect(ChatLoadingIndicatorLogic.presentation(isLoading: true, messageCount: 0) == .centered)
    }

    @Test("Inline while existing messages refresh")
    func inlineForRefresh() {
        #expect(ChatLoadingIndicatorLogic.presentation(isLoading: true, messageCount: 12) == .inline)
    }
}
