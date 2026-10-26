import Foundation
import Testing
@testable import myCoder

@Suite("Tool approval center", .serialized)
struct ToolApprovalCenterTests {

    @Test("A verdict answered before the loop awaits is buffered")
    @MainActor
    func buffersEarlyVerdict() async {
        let center = ToolApprovalCenter.shared
        center.resetForTesting()
        center.register(.fixture(id: "early"), sessionID: "s1", assistantID: "a1")

        center.resolve(id: "early", approved: true)

        #expect(await center.awaitVerdict(id: "early") == true)
        #expect(center.pendingCount(in: "s1") == 0)
    }

    @Test("Awaiting suspends until the user resolves the queued call")
    @MainActor
    func awaitBlocksUntilResolved() async {
        let center = ToolApprovalCenter.shared
        center.resetForTesting()
        center.register(.fixture(id: "blocked"), sessionID: "s1", assistantID: "a1")

        let task = Task { @MainActor in
            await center.awaitVerdict(id: "blocked")
        }
        try? await Task.sleep(nanoseconds: 30_000_000)
        #expect(center.pendingCount(in: "s1") == 1)

        center.resolve(id: "blocked", approved: true)

        #expect(await task.value == true)
        #expect(center.pendingCount(in: "s1") == 0)
    }

    @Test("Cancelling one chat denies only that chat")
    @MainActor
    func cancelIsScopedToSession() async {
        let center = ToolApprovalCenter.shared
        center.resetForTesting()
        center.register(.fixture(id: "a"), sessionID: "s1", assistantID: "a1")
        center.register(.fixture(id: "b"), sessionID: "s2", assistantID: "a2")

        center.cancelPending(in: "s1")
        center.resolve(id: "b", approved: true)

        #expect(await center.awaitVerdict(id: "a") == false)
        #expect(await center.awaitVerdict(id: "b") == true)
    }

    @Test("Pending approvals can be reattached after switching chats")
    @MainActor
    func pendingApprovalsSurviveSessionSwitch() async {
        let center = ToolApprovalCenter.shared
        center.resetForTesting()
        center.register(
            .fixture(id: "kept", callID: "call-1", tool: "write_file"),
            sessionID: "s1",
            assistantID: "assistant-1"
        )

        let pending = center.pendingApprovals(in: "s1")
        #expect(pending.map(\.id) == ["kept"])
        #expect(center.assistantID(for: "kept") == "assistant-1")
        #expect(center.pendingApprovals(in: "s2").isEmpty)

        center.resolve(id: "kept", approved: false)
        #expect(center.pendingApprovals(in: "s1").isEmpty)
    }

    @Test("Multiple queued approvals resolve independently")
    @MainActor
    func multipleApprovalsAreIndependent() async {
        let center = ToolApprovalCenter.shared
        center.resetForTesting()
        center.register(.fixture(id: "first"), sessionID: "s1", assistantID: "a1")
        center.register(.fixture(id: "second"), sessionID: "s1", assistantID: "a1")

        center.resolve(id: "second", approved: false)
        center.resolve(id: "first", approved: true)

        #expect(await center.awaitVerdict(id: "first") == true)
        #expect(await center.awaitVerdict(id: "second") == false)
        #expect(center.pendingCount(in: "s1") == 0)
    }

    @Test("Approvals are reattached by assistant message id, not by session id")
    @MainActor
    func reattachMatchesAssistantMessageID() async {
        let center = ToolApprovalCenter.shared
        center.resetForTesting()
        center.register(
            .fixture(id: "card", callID: "call-1", tool: "write_file"),
            sessionID: "session-that-moved",
            assistantID: "assistant-7"
        )
        center.register(
            .fixture(id: "other", callID: "call-2", tool: "write_file"),
            sessionID: "another-session",
            assistantID: "assistant-8"
        )

        let grouped = center.pendingApprovals(matchingAssistantIDs: ["assistant-7", "assistant-9"])

        #expect(grouped.keys.sorted() == ["assistant-7"])
        #expect(grouped["assistant-7"]?.map(\.id) == ["card"])
        #expect(center.pendingCount(in: "session-that-moved") == 1)
    }
}


private extension PendingToolApproval {
    static func fixture(
        id: String,
        callID: String = "call",
        tool: String = "write_file"
    ) -> PendingToolApproval {
        PendingToolApproval(
            id: id,
            callID: callID,
            tool: tool,
            message: "approval",
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }
}
