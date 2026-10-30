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

    /// Direct OpenAI-compatible providers stream one reasoning block per API
    /// request, and a single request can execute several tool calls. The turn
    /// is therefore a timeline: reasoning of iteration N, then iteration N's
    /// calls, then iteration N+1's reasoning, and only at the very end the
    /// answer. Merging every reasoning block above every call (the previous
    /// behaviour) destroyed the order the user needs to follow the model's
    /// train of thought.
    static func directTimelineParts(
        timeline: [MessagePartContent],
        answer: String
    ) -> [MessagePartContent] {
        var parts = timeline
        appendAnswer(answer, to: &parts)
        return parts
    }

    /// Live update while a direct iteration is still streaming: the completed
    /// timeline first (previous reasoning + calls), then the reasoning of the
    /// iteration that is currently arriving, then its answer text.
    static func directStreamingParts(
        timeline: [MessagePartContent],
        reasoning: String?,
        answer: String
    ) -> [MessagePartContent] {
        var parts = timeline
        if let reasoning, !reasoning.isEmpty {
            parts.append(.reasoning(reasoning))
        }
        appendAnswer(answer, to: &parts)
        return parts
    }

    /// Direct OpenAI-compatible providers used to merge the whole thinking
    /// channel into one block on top of every call. Kept for the single-shot
    /// path (no tool loop), where there is no timeline to preserve.
    static func directParts(
        reasoning: String?,
        toolParts: [MessagePartContent],
        answer: String
    ) -> [MessagePartContent] {
        directTimelineParts(
            timeline: (reasoning.map { $0.isEmpty ? [] : [.reasoning($0)] } ?? []) + toolParts,
            answer: answer
        )
    }

    private static func appendAnswer(_ answer: String, to parts: inout [MessagePartContent]) {
        guard !answer.isEmpty else { return }
        // Never duplicate the same answer when a provider already supplied a
        // text part (or an interrupted turn is resumed).
        if case .text(let last)? = parts.last, last == answer { return }
        var display = answer
        // Tool calls are already represented as their own parts (spoilers);
        // strip the raw ```tool fences so the answer text does not show them a
        // second time (user directive 2026-10-29).
        if parts.contains(where: {
            if case .toolCall = $0 { return true }
            return false
        }) {
            display = WebToolProtocolEmulator.strippingToolFences(from: display)
        }
        guard !display.isEmpty else { return }
        parts.append(.text(display))
    }
}
