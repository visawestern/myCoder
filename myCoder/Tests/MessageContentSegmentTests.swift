import Foundation
import Testing
@testable import myCoder

/// The chat must show the agent's turn exactly in the order it happened:
/// reasoning → tool call → reasoning → tool call → answer. Grouping is allowed
/// only for *adjacent* blocks of the same kind (user report 2026-10-29: all
/// reasoning was merged on top and all calls below it, so the train of thought
/// could not be followed).
@Suite("Порядок рассуждений и вызовов инструментов")
struct MessageContentSegmentTests {

    private func kinds(_ segments: [MessageContentSegment]) -> [String] {
        segments.map { segment in
            switch segment {
            case .part(let part):
                if case .text = part { return "text" }
                return "part"
            case .reasoning(let blocks): return "reasoning(\(blocks.count))"
            case .toolCalls(let calls): return "tools(\(calls.count))"
            case .approval: return "approval"
            }
        }
    }

    private func tool(_ name: String, callID: String? = nil) -> MessagePartContent {
        .toolCall(name: name, args: "{}", result: "ok", callID: callID ?? name)
    }

    @Test("Рассуждение и тулы чередуются, а не слипаются в два блока")
    func reasoningAndToolsKeepTheirOrder() {
        let parts: [MessagePartContent] = [
            .reasoning("думаю 1"),
            tool("grep"),
            .reasoning("думаю 2"),
            tool("read_file"),
            .text("ответ")
        ]
        #expect(kinds(MessageContentSegment.build(from: parts))
                == ["reasoning(1)", "tools(1)", "reasoning(1)", "tools(1)", "text"])
    }

    @Test("Подряд идущие рассуждения объединяются в один спойлер")
    func adjacentReasoningBlocksMerge() {
        let parts: [MessagePartContent] = [
            .reasoning("часть 1"),
            .reasoning("часть 2"),
            .text("ответ")
        ]
        #expect(kinds(MessageContentSegment.build(from: parts))
                == ["reasoning(2)", "text"])
    }

    @Test("Разделённые рассуждением тулы остаются отдельными панелями")
    func toolsSplitByReasoningStaySeparate() {
        let parts: [MessagePartContent] = [
            tool("grep"),
            tool("grep"),
            .reasoning("между вызовами"),
            tool("read_file")
        ]
        #expect(kinds(MessageContentSegment.build(from: parts))
                == ["tools(2)", "reasoning(1)", "tools(1)"])
    }

    @Test("Подряд идущие тулы группируются в одну панель")
    func adjacentToolsGroup() {
        let parts: [MessagePartContent] = [tool("grep"), tool("read_file"), .text("итог")]
        #expect(kinds(MessageContentSegment.build(from: parts)) == ["tools(2)", "text"])
    }

    @Test("Маршрутные чипы не разрывают группы")
    func routeChipsDoNotBreakGroups() {
        let parts: [MessagePartContent] = [
            .reasoning("думаю"),
            .routeInfo(chips: ["model"]),
            .reasoning("ещё думаю"),
            tool("grep")
        ]
        #expect(kinds(MessageContentSegment.build(from: parts))
                == ["reasoning(2)", "tools(1)"])
    }

    @Test("Одобрение идёт сразу после своего вызова")
    func approvalCardFollowsItsCall() {
        let approval = PendingToolApproval(
            id: "a1",
            callID: "c1",
            tool: "write_file",
            message: "allow?",
            createdAt: Date()
        )
        let parts: [MessagePartContent] = [
            .reasoning("думаю"),
            tool("grep"),
            tool("write_file", callID: "c1"),
            tool("read_file")
        ]
        #expect(kinds(MessageContentSegment.build(from: parts, approvals: [approval]))
                == ["reasoning(1)", "tools(1)", "tools(1)", "approval", "tools(1)"])
    }
}
