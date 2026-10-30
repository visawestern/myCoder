import Testing
@testable import myCoder

@Suite("myCoder Auto Free conversation context")
struct MyCoderAutoFreeHistoryLogicTests {
    @Test("multi-turn history preserves prior finished turns and drops in-flight placeholders")
    func preservesPriorConversationTurns() {
        let history = MyCoderAutoFreeHistoryLogic.history(from: [
            .init(role: "user", content: "Remember project name", isFinished: true),
            .init(role: "assistant", content: "myCoder", isFinished: true),
            .init(role: "assistant", content: "in-flight placeholder", isFinished: false)
        ])
        #expect(history.map(\.role) == ["user", "assistant"])
        #expect(history.map(\.content) == ["Remember project name", "myCoder"])
    }

    @Test("history limit keeps only the newest finished turns and zero disables history")
    func historyLimitEdges() {
        let turns = (1...3).map {
            MyCoderAutoFreeHistoryLogic.Turn(role: "user", content: "turn \($0)", isFinished: true)
        }
        #expect(MyCoderAutoFreeHistoryLogic.history(from: turns, maxTurns: 2).map(\.content) == ["turn 2", "turn 3"])
        #expect(MyCoderAutoFreeHistoryLogic.history(from: turns, maxTurns: 0).isEmpty)
    }

    @Test("unfinished prior user turns are excluded just like unfinished assistant placeholders")
    func dropsUnfinishedUserTurns() {
        let history = MyCoderAutoFreeHistoryLogic.history(from: [
            .init(role: "user", content: "submitted", isFinished: true),
            .init(role: "assistant", content: "reply", isFinished: true),
            .init(role: "user", content: "still streaming", isFinished: false)
        ])
        #expect(history.map(\.content) == ["submitted", "reply"])
    }

    @Test("negative history limits fail closed instead of disabling the cap")
    func negativeLimitDisablesHistory() {
        let turns = [
            MyCoderAutoFreeHistoryLogic.Turn(role: "user", content: "old", isFinished: true),
            MyCoderAutoFreeHistoryLogic.Turn(role: "assistant", content: "reply", isFinished: true)
        ]
        #expect(MyCoderAutoFreeHistoryLogic.history(from: turns, maxTurns: -1).isEmpty)
    }
}
