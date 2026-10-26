import Testing
@testable import myCoder

@Suite("INP-10 send button activation")
struct SendButtonActivationLogicTests {
    @Test("keyboard send is allowed when ready and idle")
    func readyIdleAllowsSend() {
        #expect(SendButtonActivationLogic.canInvokeSend(canSend: true, isLoading: false))
    }

    @Test("invalid readiness blocks keyboard send")
    func invalidReadinessBlocksSend() {
        #expect(!SendButtonActivationLogic.canInvokeSend(canSend: false, isLoading: false))
    }

    @Test("a running turn still accepts the message — it is queued")
    func loadingQueuesInsteadOfBlocking() {
        #expect(SendButtonActivationLogic.canInvokeSend(canSend: true, isLoading: true))
    }

    @Test("empty composer stays blocked while running")
    func loadingWithoutContentBlocksSend() {
        #expect(!SendButtonActivationLogic.canInvokeSend(canSend: false, isLoading: true))
    }

    @Test("a queued message can always be forced out")
    func forceQueueIsAvailable() {
        #expect(SendButtonActivationLogic.canInvokeQueue(canSend: false, isLoading: true))
    }
}
