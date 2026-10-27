import Foundation

enum MessageDisplayLogic {

    static func messagesForDisplay(_ messages: [Message]) -> [Message] {
        let merged = mergeConsecutiveThinkingOnly(messages)
        let folded = foldThinkingIntoFollowingReply(merged)
        let consolidated = consolidateReasoningByTurn(folded)
        return consolidated.filter { shouldDisplay($0, in: consolidated) }
    }

    /// A single answer can arrive as several assistant messages (one per tool
    /// round). The user-facing reasoning spoiler must stay one block per turn,
    /// so every chunk is moved to the first assistant message of the turn and
    /// stripped from the later ones. User messages mark turn boundaries.
    static func consolidateReasoningByTurn(_ messages: [Message]) -> [Message] {
        var result = messages
        var turnStart: Int?

        func flushTurn(until end: Int) {
            guard let start = turnStart else { return }
            turnStart = nil

            let assistantIndices = (start..<end).filter { result[$0].role == .assistant }
            guard assistantIndices.count > 1 else { return }
            // Keep live reasoning in the streaming bubble: moving it to an
            // already-finished message would collapse the spoiler mid-turn.
            guard !assistantIndices.contains(where: { result[$0].isStreaming }) else { return }

            var chunks: [String] = []
            var startedAt: Date?
            var endedAt: Date?
            for index in assistantIndices {
                let message = result[index]
                appendReasoning(message.reasoning, into: &chunks)
                for part in message.parts {
                    if case .reasoning(let text) = part {
                        appendReasoning(text, into: &chunks)
                    }
                }
                if startedAt == nil { startedAt = message.reasoningStartedAt }
                if let messageEnd = message.reasoningEndedAt { endedAt = messageEnd }
            }
            guard !chunks.isEmpty else { return }

            let combined = chunks.joined(separator: "\n\n")
            let anchor = assistantIndices[0]
            result[anchor] = attachingReasoning(
                combined,
                to: result[anchor],
                startedAt: startedAt,
                endedAt: endedAt
            )
            for index in assistantIndices.dropFirst() {
                result[index] = removingReasoning(from: result[index])
            }
        }

        for (index, message) in messages.enumerated() where message.role == .user {
            flushTurn(until: index)
            turnStart = index + 1
        }
        flushTurn(until: messages.count)
        return result
    }

    static func hasVisibleAnswer(_ message: Message) -> Bool {
        hasVisibleText(message) || hasToolCalls(message)
    }

    static func deduplicatedReasoning(_ message: Message) -> String {
        var chunks: [String] = []
        appendReasoning(message.reasoning, into: &chunks)
        for part in message.parts {
            if case .reasoning(let text) = part {
                appendReasoning(text, into: &chunks)
            }
        }
        return chunks.joined(separator: "\n\n")
    }

    static func foldThinkingIntoFollowingReply(_ messages: [Message]) -> [Message] {
        var result: [Message] = []
        var index = 0

        while index < messages.count {
            let current = messages[index]
            if index + 1 < messages.count,
               isThinkingOnly(current),
               messages[index + 1].role == .assistant,
               hasVisibleText(messages[index + 1]) {
                var reply = messages[index + 1]
                let combined = combinedReasoning(from: current, and: reply)
                reply.reasoning = combined
                reply.parts.removeAll { part in
                    if case .reasoning = part { return true }
                    return false
                }
                if !combined.isEmpty {
                    reply.parts.insert(.reasoning(combined), at: 0)
                }
                reply.parts = mergeExecutionStepParts(from: current.parts, into: reply.parts)
                result.append(reply)
                index += 2
                continue
            }

            if isThinkingOnly(current), !hasReasoningContent(current), !current.isStreaming {
                index += 1
                continue
            }

            result.append(current)
            index += 1
        }

        return result
    }

    private static func combinedReasoning(from thinking: Message, and reply: Message) -> String {
        var chunks: [String] = []
        appendReasoning(deduplicatedReasoning(thinking), into: &chunks)
        appendReasoning(deduplicatedReasoning(reply), into: &chunks)
        return chunks.joined(separator: "\n\n")
    }

    static func isThinkingOnly(_ message: Message) -> Bool {
        guard message.role == .assistant else { return false }
        if hasVisibleText(message) { return false }
        if hasToolCalls(message) { return false }
        if message.attachedImages?.isEmpty == false { return false }
        if hasImageParts(message) { return false }
        if message.tokensAdded != nil || message.tokensRemoved != nil { return false }

        if hasReasoningContent(message) { return true }
        if hasStepMarkers(message) { return true }
        if message.isStreaming && message.content.isEmpty && message.reasoning.isEmpty {
            return true
        }
        return false
    }

    static func shouldDisplay(_ message: Message) -> Bool {
        if message.role != .assistant { return true }
        if isThinkingOnly(message) {
            return hasReasoningContent(message) || message.isStreaming || hasStepMarkers(message)
        }
        return !isEmptyAssistantShell(message)
    }

    static func groupPartsByExecutionSteps(_ parts: [MessagePartContent]) -> [ExecutionStepSegment] {
        var segments: [ExecutionStepSegment] = []
        var stepIndex = 0
        var buffer: [MessagePartContent] = []
        var inStep = false

        func flushPreamble() {
            guard !buffer.isEmpty else { return }
            segments.append(
                ExecutionStepSegment(
                    id: "preamble-\(segments.count)",
                    stepNumber: 0,
                    isComplete: true,
                    isActive: false,
                    parts: buffer
                )
            )
            buffer = []
        }

        for part in parts {
            switch part {
            case .stepStart:
                flushPreamble()
                stepIndex += 1
                inStep = true
            case .stepFinish:
                segments.append(
                    ExecutionStepSegment(
                        id: "step-\(stepIndex)-\(segments.count)",
                        stepNumber: stepIndex,
                        isComplete: true,
                        isActive: false,
                        parts: buffer
                    )
                )
                buffer = []
                inStep = false
            case .reasoning:
                continue
            default:
                buffer.append(part)
            }
        }

        if !buffer.isEmpty {
            if inStep, stepIndex > 0 {
                segments.append(
                    ExecutionStepSegment(
                        id: "step-\(stepIndex)-active",
                        stepNumber: stepIndex,
                        isComplete: false,
                        isActive: true,
                        parts: buffer
                    )
                )
            } else {
                flushPreamble()
            }
        }

        return segments
    }

    static func mergeExecutionStepParts(
        from source: [MessagePartContent],
        into target: [MessagePartContent]
    ) -> [MessagePartContent] {
        let markers = source.filter(isExecutionStepMarker)
        guard !markers.isEmpty else { return target }

        var merged = markers
        for part in target where !isExecutionStepMarker(part) {
            merged.append(part)
        }
        return merged
    }

    static func isExecutionStepMarker(_ part: MessagePartContent) -> Bool {
        if case .stepStart = part { return true }
        if case .stepFinish = part { return true }
        return false
    }

    static func chatDisplayParts(_ parts: [MessagePartContent]) -> [MessagePartContent] {
        parts.filter { !isExecutionStepMarker($0) }
    }

    static func shouldDisplay(_ message: Message, in allMessages: [Message]) -> Bool {
        if isRedundantStreamingShell(message, in: allMessages) { return false }
        return shouldDisplay(message)
    }

    static func hasImageParts(_ message: Message) -> Bool {
        message.parts.contains { part in
            if case .image = part { return true }
            return false
        }
    }

    /// Legacy `attachedImages` are ignored when the same images already live in `parts`.
    static func attachedImagesForDisplay(_ message: Message) -> [ClipboardImage] {
        guard !hasImageParts(message), let attached = message.attachedImages else { return [] }
        return attached
    }

    static func isEmptyAssistantShell(_ message: Message) -> Bool {
        guard message.role == .assistant else { return false }
        if message.isStreaming { return false }
        if hasVisibleText(message) { return false }
        if hasToolCalls(message) { return false }
        if hasReasoningContent(message) { return false }
        if message.attachedImages?.isEmpty == false { return false }
        if hasImageParts(message) { return false }
        if message.tokensAdded != nil || message.tokensRemoved != nil { return false }
        return true
    }

    static func isRedundantStreamingShell(_ message: Message, in messages: [Message]) -> Bool {
        guard message.role == .assistant, message.isStreaming else { return false }
        guard !hasVisibleAnswer(message), !hasReasoningContent(message) else { return false }
        guard let idx = messages.firstIndex(where: { $0.id == message.id }) else { return false }
        return messages[(idx + 1)...].contains { $0.role == .assistant && (hasVisibleAnswer($0) || hasReasoningContent($0)) }
    }

    static func mergeConsecutiveThinkingOnly(_ messages: [Message]) -> [Message] {
        var result: [Message] = []
        var buffer: [Message] = []

        func flushBuffer() {
            guard !buffer.isEmpty else { return }
            if buffer.count == 1 {
                result.append(buffer[0])
            } else {
                result.append(mergedMessage(from: buffer))
            }
            buffer = []
        }

        for message in messages {
            if isThinkingOnly(message) {
                buffer.append(message)
            } else {
                flushBuffer()
                result.append(message)
            }
        }
        flushBuffer()
        return result
    }

    static func mergedMessage(from messages: [Message]) -> Message {
        guard let first = messages.first, let last = messages.last else {
            return messages[0]
        }

        var reasoningChunks: [String] = []
        var extraParts: [MessagePartContent] = []

        for message in messages {
            appendReasoning(message.reasoning, into: &reasoningChunks)
            for part in message.parts {
                switch part {
                case .reasoning(let text):
                    appendReasoning(text, into: &reasoningChunks)
                case .stepStart, .stepFinish:
                    continue
                case .text, .toolCall, .image:
                    extraParts.append(part)
                case .routeInfo:
                    // Route metadata renders in the header chips only.
                    continue
                case .compiledContext:
                    // The point context has its own button under the message.
                    continue
                }
            }
        }

        let combinedReasoning = reasoningChunks.joined(separator: "\n\n")
        var parts: [MessagePartContent] = []
        if !combinedReasoning.isEmpty {
            parts.append(.reasoning(combinedReasoning))
        }
        parts.append(contentsOf: extraParts)

        return Message(
            id: last.id,
            role: .assistant,
            content: "",
            parts: parts,
            reasoning: combinedReasoning,
            isFinished: !messages.contains(where: \.isStreaming),
            reasoningStartedAt: first.reasoningStartedAt ?? last.reasoningStartedAt
        )
    }

    private static func hasVisibleText(_ message: Message) -> Bool {
        if !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return message.parts.contains { part in
            if case .text(let text) = part, !text.isEmpty { return true }
            return false
        }
    }

    private static func hasToolCalls(_ message: Message) -> Bool {
        message.parts.contains { part in
            if case .toolCall = part { return true }
            return false
        }
    }

    private static func hasReasoningContent(_ message: Message) -> Bool {
        if !message.reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return message.parts.contains { part in
            if case .reasoning(let text) = part, !text.isEmpty { return true }
            return false
        }
    }

    private static func hasStepMarkers(_ message: Message) -> Bool {
        message.parts.contains { part in
            if case .stepStart = part { return true }
            if case .stepFinish = part { return true }
            return false
        }
    }

    private static func attachingReasoning(_ reasoning: String,
                                           to message: Message,
                                           startedAt: Date?,
                                           endedAt: Date?) -> Message {
        var copy = message
        copy.reasoning = reasoning
        var parts = message.parts.filter { part in
            if case .reasoning = part { return false }
            return true
        }
        parts.insert(.reasoning(reasoning), at: 0)
        copy.parts = parts
        copy.reasoningStartedAt = startedAt ?? message.reasoningStartedAt
        copy.reasoningEndedAt = endedAt ?? message.reasoningEndedAt
        return copy
    }

    private static func removingReasoning(from message: Message) -> Message {
        var copy = message
        copy.reasoning = ""
        copy.parts = message.parts.filter { part in
            if case .reasoning = part { return false }
            return true
        }
        copy.reasoningStartedAt = nil
        copy.reasoningEndedAt = nil
        return copy
    }

    private static func appendReasoning(_ text: String, into chunks: inout [String]) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if chunks.last != trimmed {
            chunks.append(trimmed)
        }
    }
}
