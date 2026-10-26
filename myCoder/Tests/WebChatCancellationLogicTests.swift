import Testing
@testable import myCoder

@Suite("WEB-05/WEB-07 web turn cancellation")
struct WebChatCancellationLogicTests {
    @Test("cancelled web driver turn aborts post-driver completion handling")
    func cancelledTurnStopsPostDriverFlow() {
        #expect(WebChatCancellationLogic.shouldStopAfterDriver(isCancelled: true))
        #expect(!WebChatCancellationLogic.shouldStopAfterDriver(isCancelled: false))
    }
}
