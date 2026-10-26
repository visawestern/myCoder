import Testing
@testable import myCoder

struct SpecNodePromptFlushLogicTests {
    private func shouldFlush(
        pending: String? = "chat-1",
        selected: String? = "chat-1",
        current: String? = "chat-1",
        loaded: String? = "chat-1",
        loadingMessages: Bool = false,
        busy: Bool = false
    ) -> Bool {
        SpecNodePromptFlushLogic.shouldFlush(
            pendingSessionID: pending,
            selectedSessionID: selected,
            currentSessionID: current,
            loadedSessionID: loaded,
            isLoadingMessages: loadingMessages,
            isBusy: busy
        )
    }

    private func needsLoad(
        pending: String? = "chat-1",
        selected: String? = "chat-1",
        loaded: String? = nil,
        loadingMessages: Bool = false
    ) -> Bool {
        SpecNodePromptFlushLogic.needsHistoryLoad(
            pendingSessionID: pending,
            selectedSessionID: selected,
            loadedSessionID: loaded,
            isLoadingMessages: loadingMessages
        )
    }

    @Test("A selected pending chat with unloaded history requests its own load")
    func loadsWhenSelectionDidNotTriggerIt() {
        #expect(needsLoad())
        #expect(needsLoad(loaded: "chat-0"))
    }

    @Test("No history load starts for an unselected or already loaded chat")
    func doesNotReloadNeedlessly() {
        #expect(!needsLoad(selected: "chat-2"))
        #expect(!needsLoad(pending: nil))
        #expect(!needsLoad(loaded: "chat-1"))
        #expect(!needsLoad(loadingMessages: true))
    }

    @Test("Prompt is sent only when every session marker matches and nothing is loading")
    func sendsWhenReady() {
        #expect(shouldFlush())
    }

    @Test("No pending prompt means nothing to send")
    func noPendingPrompt() {
        #expect(!shouldFlush(pending: nil))
    }

    @Test("Prompt waits for the selected session")
    func waitsForSelection() {
        #expect(!shouldFlush(selected: "chat-2"))
        #expect(!shouldFlush(selected: nil))
    }

    @Test("Prompt waits for the store to point at its session")
    func waitsForStore() {
        #expect(!shouldFlush(current: "chat-2"))
        #expect(!shouldFlush(current: nil))
    }

    @Test("Prompt waits for history to finish loading")
    func waitsForHistory() {
        #expect(!shouldFlush(loaded: nil))
        #expect(!shouldFlush(loaded: "chat-2"))
    }

    @Test("Prompt is not sent while a load or another request is in flight")
    func waitsForIdle() {
        #expect(!shouldFlush(loadingMessages: true))
        #expect(!shouldFlush(busy: true))
    }
}
