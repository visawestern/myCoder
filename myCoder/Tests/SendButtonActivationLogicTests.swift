import Testing
@testable import myCoder

@Suite("INP-10 send button activation")
struct SendButtonActivationLogicTests {
    @Test("keyboard send is allowed only when ready and idle")
    func readyIdleAllowsSend() {
        #expect(SendButtonActivationLogic.canInvokeSend(canSend: true, isLoading: false))
    }

    @Test("invalid readiness blocks keyboard send")
    func invalidReadinessBlocksSend() {
        #expect(!SendButtonActivationLogic.canInvokeSend(canSend: false, isLoading: false))
    }

    @Test("loading state keeps Enter on stop semantics")
    func loadingBlocksKeyboardSend() {
        #expect(!SendButtonActivationLogic.canInvokeSend(canSend: true, isLoading: true))
    }
}
