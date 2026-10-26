import Foundation
import Testing
@testable import myCoder

@Suite("ERR-01 session busy retry")
struct SessionBusyRetryLogicTests {
    @Test("retry stops after three recovery attempts")
    func retryIsBounded() {
        #expect(SessionBusyRetryLogic.shouldRetry(retryCount: 0))
        #expect(SessionBusyRetryLogic.shouldRetry(retryCount: 2))
        #expect(!SessionBusyRetryLogic.shouldRetry(retryCount: 3))
        #expect(!SessionBusyRetryLogic.shouldRetry(retryCount: 99))
    }

    @Test("retry keeps the original turn and remote session identity")
    func retryReusesTurnIdentity() throws {
        let current = SessionBusyRetryLogic.RetryPlan(
            retryCount: 0,
            sessionID: "remote-session",
            assistantMessageID: "assistant-message",
            messageID: "request-message"
        )
        let next = try #require(SessionBusyRetryLogic.nextPlan(from: current))
        #expect(next.retryCount == 1)
        #expect(next.sessionID == current.sessionID)
        #expect(next.assistantMessageID == current.assistantMessageID)
        #expect(next.messageID == current.messageID)
    }

    @Test("cancelled busy recovery does not create another retry plan")
    func cancellationStopsRetry() throws {
        let current = SessionBusyRetryLogic.RetryPlan(
            retryCount: 0,
            sessionID: "remote-session",
            assistantMessageID: "assistant-message",
            messageID: "request-message"
        )
        #expect(SessionBusyRetryLogic.nextPlan(from: current, isCancelled: true) == nil)
        #expect(SessionBusyRetryLogic.nextPlan(from: current, isCancelled: false) != nil)
    }
}
