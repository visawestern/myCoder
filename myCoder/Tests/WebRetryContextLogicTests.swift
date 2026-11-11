import Testing
@testable import myCoder

@MainActor
@Suite("WEB-26 retry context coherence")
struct WebRetryContextLogicTests {
    @Test("catalog refresh retry preserves existing remote chat context")
    func retryPreservesFirstMessageFlag() {
        #expect(!WebRetryContextLogic.isFirstMessageForRetry(originalIsFirst: false))
        #expect(WebRetryContextLogic.isFirstMessageForRetry(originalIsFirst: true))
    }
}
