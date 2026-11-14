import SwiftUI
enum MessageContentSegment: Identifiable {
    case part(MessagePartContent)
    /// Consecutive thinking blocks of one agent iteration (or the same
    /// iteration split by the provider). They are merged into ONE spoiler,
    /// because they belong to the same thought. A thinking block that follows
    /// a tool call is a NEW thought and gets its own spoiler, so the chat keeps
    /// the exact order: reasoning → tool → reasoning → tool → answer.
    case reasoning([String])
    case toolCalls([ToolCallInspectorStep])
    case approval(PendingToolApproval)

    var id: String {
        switch self {
        case .part(let part):
            return "part-\(part.id)"
        case .reasoning(let blocks):
            return "reasoning-\(blocks.joined(separator: "\u{1}").hashValue)"
        case .toolCalls(let calls):
            return "tools-\(calls.first?.id ?? "empty")"
        case .approval(let approval):
            return "approval-\(approval.id)"
        }
    }

    static func build(
        from parts: [MessagePartContent],
        approvals: [PendingToolApproval] = [],
        toolResultMeta: [String: ToolResultMeta] = [:]
    ) -> [MessageContentSegment] {
        var segments: [MessageContentSegment] = []
        var calls: [ToolCallInspectorStep] = []
        var reasoning: [String] = []
        var remainingApprovals = approvals

        func flushCalls() {
            guard !calls.isEmpty else { return }
            segments.append(.toolCalls(calls))
            calls = []
        }

        func flushReasoning() {
            guard !reasoning.isEmpty else { return }
            segments.append(.reasoning(reasoning))
            reasoning = []
        }

        for part in parts {
            if case .routeInfo = part {
                // Route chips render in the header, not in the content flow.
                continue
            }
            if case .reasoning(let text) = part {
                flushCalls()
                if !text.isEmpty { reasoning.append(text) }
                continue
            }
            if case .toolCall(let name, let args, let result, let callID) = part {
                flushReasoning()
                // При lite-загрузке истории результат ещё не прочитан:
                // флаг hasStoredResult говорит, что он существует в
                // хранилище, и спойлер подгрузит его лениво.
                let storedMeta = callID.flatMap { toolResultMeta[$0] }
                let step = ToolCallInspectorStep(
                    id: part.id,
                    name: name,
                    args: args,
                    result: result,
                    callID: callID,
                    hasStoredResult: storedMeta?.hasStoredResult ?? false
                )
                if let callID,
                   let approvalIndex = remainingApprovals.firstIndex(where: { $0.callID == callID }) {
                    // Keep the card directly after its own call instead of
                    // after the whole grouped tool spoiler.
                    flushCalls()
                    segments.append(.toolCalls([step]))
                    segments.append(.approval(remainingApprovals.remove(at: approvalIndex)))
                } else {
                    calls.append(step)
                }
            } else {
                flushReasoning()
                flushCalls()
                segments.append(.part(part))
            }
        }
        flushReasoning()
        flushCalls()
        for approval in remainingApprovals {
            segments.append(.approval(approval))
        }
        return segments
    }
}

/// Compact metadata chips shown above an assistant message produced through a
/// web provider (provider · model · effort · remote chat). Kept out of the
/// message content — the copy button copies only the model's answer.
