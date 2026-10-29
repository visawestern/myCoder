import Foundation

/// Builds the display parts of an assistant turn for the local tool-loop
/// providers.
///
/// These paths used to store only reasoning and tool-call parts. The answer
/// text lived in `content` alone, which the row renders *before* the parts
/// flow — so a finished reply showed the answer first and its reasoning block
/// underneath (the user reported reasoning "at the very end"). The answer is
/// now a real text part placed after the turn's calls, and reasoning stays
/// where it happened.
enum AssistantTurnPartsLogic {

    /// Direct OpenAI-compatible providers merge the whole thinking channel
    /// into one block. It belongs on top, then the executed calls in order,
    /// then the final answer.
    static func directParts(
        reasoning: String?,
        toolParts: [MessagePartContent],
        answer: String
    ) -> [MessagePartContent] {
        var parts: [MessagePartContent] = []
        if let reasoning, !reasoning.isEmpty {
            parts.append(.reasoning(reasoning))
        }
        parts.append(contentsOf: toolParts)
        appendAnswer(answer, to: &parts)
        return parts
    }

    /// Auto Free keeps each iteration's reasoning inline, already positioned
    /// before that iteration's calls. Only the answer needs appending.
    static func autoFreeFinalParts(
        timelineParts: [MessagePartContent],
        answer: String
    ) -> [MessagePartContent] {
        var parts = timelineParts
        appendAnswer(answer, to: &parts)
        return parts
    }

    /// Live update while an Auto Free iteration streams: reasoning first,
    /// then the text produced in that iteration.
    static func autoFreeStreamingParts(
        timelineParts: [MessagePartContent],
        reasoning: String,
        answer: String
    ) -> [MessagePartContent] {
        var parts = timelineParts
        if !reasoning.isEmpty {
            parts.append(.reasoning(reasoning))
        }
        appendAnswer(answer, to: &parts)
        return parts
    }

    private static func appendAnswer(_ answer: String, to parts: inout [MessagePartContent]) {
        guard !answer.isEmpty else { return }
        // Never duplicate the same answer when a provider already supplied a
        // text part (or an interrupted turn is resumed).
        if case .text(let last)? = parts.last, last == answer { return }
        parts.append(.text(answer))
    }
}
