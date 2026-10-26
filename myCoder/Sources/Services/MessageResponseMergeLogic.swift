import Foundation

enum MessageResponseMergeLogic {

    static func mergedAssistantMessage(
        existing: Message,
        serverParts: [MimoMessagePart]?,
        serverText: String,
        streamingText: String
    ) -> (content: String, reasoning: String, parts: [MessagePartContent]) {
        let resolvedContent = resolvedText(
            serverText: serverText,
            existingContent: existing.content,
            streamingText: streamingText
        )

        if let serverParts, !serverParts.isEmpty {
            let parsed = parts(from: serverParts)
            let reasoning = parsed.reasoning.isEmpty ? existing.reasoning : parsed.reasoning
            return (resolvedContent, reasoning, deduplicatedParts(parsed.parts))
        }

        var parts = existing.parts
        if !resolvedContent.isEmpty {
            upsertTextPart(&parts, text: resolvedContent)
        }
        if !existing.reasoning.isEmpty {
            upsertReasoningPart(&parts, text: existing.reasoning)
        }
        return (resolvedContent, existing.reasoning, deduplicatedParts(parts))
    }

    static func resolvedText(serverText: String, existingContent: String, streamingText: String) -> String {
        if !serverText.isEmpty { return serverText }
        if !existingContent.isEmpty { return existingContent }
        return streamingText
    }

    static func upsertTextPart(_ parts: inout [MessagePartContent], text: String) {
        guard !text.isEmpty else { return }
        if let index = parts.lastIndex(where: { if case .text = $0 { return true }; return false }) {
            parts[index] = .text(text)
        } else {
            parts.append(.text(text))
        }
    }

    static func upsertReasoningPart(_ parts: inout [MessagePartContent], text: String) {
        guard !text.isEmpty else { return }
        if let index = parts.lastIndex(where: { if case .reasoning = $0 { return true }; return false }) {
            parts[index] = .reasoning(text)
        } else {
            parts.insert(.reasoning(text), at: 0)
        }
    }

    static func deduplicatedParts(_ parts: [MessagePartContent]) -> [MessagePartContent] {
        var result: [MessagePartContent] = []
        for part in parts {
            switch part {
            case .text(let text):
                if case .text(let previous)? = result.last, previous == text { continue }
                if result.contains(where: { if case .text(let existing) = $0 { return existing == text }; return false }) {
                    continue
                }
                result.append(.text(text))
            case .reasoning(let text):
                if case .reasoning(let previous)? = result.last, previous == text { continue }
                result.append(.reasoning(text))
            default:
                result.append(part)
            }
        }
        return result
    }

    static func reasoningForDisplay(_ message: Message) -> String {
        let reasoning = MessageDisplayLogic.deduplicatedReasoning(message)
        let visible = visibleText(message)
        guard !reasoning.isEmpty, !visible.isEmpty else { return reasoning }

        let normalizedReasoning = normalize(reasoning)
        let normalizedVisible = normalize(visible)
        if normalizedReasoning == normalizedVisible { return "" }
        if normalizedVisible.count > 80, normalizedReasoning.hasPrefix(normalizedVisible.prefix(120)) {
            return ""
        }
        return reasoning
    }

    static func visibleText(_ message: Message) -> String {
        var chunks: [String] = []
        for part in message.parts {
            if case .text(let value) = part, !value.isEmpty { chunks.append(value) }
        }
        if chunks.isEmpty, !message.content.isEmpty { chunks.append(message.content) }
        return chunks.joined(separator: "\n\n")
    }

    private static func parts(from serverParts: [MimoMessagePart]) -> (parts: [MessagePartContent], reasoning: String) {
        var parts: [MessagePartContent] = []
        var reasoningChunks: [String] = []

        for part in serverParts {
            switch part {
            case .text(let text):
                parts.append(.text(text))
            case .reasoning(let text):
                reasoningChunks.append(text)
                parts.append(.reasoning(text))
            case .stepStart:
                parts.append(.stepStart)
            case .stepFinish:
                parts.append(.stepFinish)
            case .toolInvocation(let name, let input, let result, let callID):
                parts.append(.toolCall(name: name, args: input ?? "{}", result: result, callID: callID))
            case .image(let mediaType, let data):
                parts.append(.image(base64: data, mimeType: mediaType))
            case .other:
                break
            }
        }

        return (parts, reasoningChunks.joined(separator: "\n\n"))
    }

    private static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\r\n", with: "\n")
    }
}
