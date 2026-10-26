import Foundation

/// AI-powered conversation summarization for web-provider session restarts.
/// When a web model hits its per-chat token limit, the full transcript is
/// summarized using the local free model (myCoder Auto Free) so the next
/// chat session can continue with compressed context focused on the current
/// task. Progressive thresholds prevent premature summarization: the allowed
/// context window grows by `stepTokens` after each restart so earlier
/// summaries stay compact while later ones carry more detail.
enum WebSessionSummarizer {

    // MARK: - Token estimation

    /// Rough token estimation: ~4 chars per token for Latin text, ~2 chars
    /// per token for CJK. Conservative enough to trigger summarization
    /// BEFORE the vendor limit.
    static func estimateTokens(in text: String) -> Int {
        var latinScalars = 0
        var cjkScalars = 0
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if (0x4E00...0x9FFF).contains(v)    // CJK Unified
                || (0x3040...0x30FF).contains(v) // Hiragana + Katakana
                || (0xAC00...0xD7AF).contains(v) // Hangul
                || (0xF900...0xFAFF).contains(v) // CJK Compatibility
            {
                cjkScalars += 1
            } else {
                latinScalars += 1
            }
        }
        let tokens = (latinScalars + 3) / 4 + (cjkScalars + 1) / 2
        return max(1, tokens)
    }

    // MARK: - Progressive thresholds

    /// Base token budget per chat session. Must stay well below what
    /// `extractTranscriptFromDOM` can return (caps at ~100k chars ≈ 25k
    /// tokens) — otherwise the proactive check can never fire (audit
    /// 2026-09-11: 64k base vs 25k max transcript made it dead code).
    /// After each restart the allowed budget increases by `stepTokens` so
    /// summaries carry progressively more context as the task deepens.
    static let baseTokens = 12_000
    static let stepTokens = 12_000

    /// Maximum tokens allowed before triggering summarization.
    /// `restartCount` is the number of previous restarts in this driver turn.
    static func maxTokensBeforeSummary(restartCount: Int) -> Int {
        baseTokens + restartCount * stepTokens
    }

    // MARK: - Summarization

    /// System prompt for the summarizer model. Demands a STRUCTURED handoff
    /// with concrete data — tool calls and their outputs, file paths, exact
    /// values — never generic filler. The next session continues the task
    /// from this summary alone, so specifics are irreplaceable.
    private static let summarySystemPrompt = """
    You are a precise conversation summarizer for a coding agent. \
    The transcript below is a raw web-chat DOM dump: it may contain UI chrome \
    (copy buttons, timestamps, navigation labels) — ignore all chrome and \
    extract only the task substance. \
    Output a structured handoff with EXACTLY these sections, in the SAME LANGUAGE as the conversation:
    TASK: the user's request in one or two sentences, plus success criteria if stated.
    DONE: each completed tool action as `tool_name(key=value)` followed by its CONCRETE output (file listings, file contents, command results, numbers, names). Never write "ran tests" — write WHAT the tests reported.
    FILES: every file path read, written, or mentioned, with the key content found or changed in each.
    DATA: exact facts discovered — error messages verbatim, values, counts, identifiers, decisions made and why.
    NEXT: the pending steps in order, with the very next action first.
    Rules:
    - Preserve exact values: paths, code, numbers, error text. A vague summary is a failed summary.
    - Drop greetings, filler, repeated explanations, and off-topic digressions.
    - Keep the whole handoff under 4000 tokens.
    """

    /// Cap for the transcript fed into the summarizer call. The DOM dump can
    /// reach ~100k chars; sending all of it wastes the free-model budget and
    /// risks truncation. Keep the head (task setup + preamble) and the tail
    /// (recent tool work) with an explicit gap marker.
    static let maxTranscriptChars = 60_000
    static let transcriptHeadChars = 10_000

    static func boundTranscript(_ transcript: String) -> String {
        guard transcript.count > maxTranscriptChars else { return transcript }
        let head = transcript.prefix(transcriptHeadChars)
        let tailChars = maxTranscriptChars - transcriptHeadChars
        let tail = transcript.suffix(tailChars)
        return head + "\n\n[... middle of the conversation omitted for length ...]\n\n" + tail
    }

    /// Summarize a conversation transcript using the local free model.
    /// Returns the summary text, or nil if summarization fails (caller
    /// falls back to the raw recent context).
    static func summarize(transcript: String, goal: String?) async -> String? {
        guard !transcript.isEmpty else { return nil }

        var userContent = ""
        if let goal, !goal.isEmpty {
            userContent += "Current task goal: \(goal)\n\n"
        }
        userContent += "Conversation to summarize:\n\n\(boundTranscript(transcript))"

        let messages: [DirectChatMessage] = [
            .init(role: "system", content: summarySystemPrompt),
            .init(role: "user", content: userContent)
        ]

        do {
            let result = try await InternalModelRunner.complete(messages: messages)
            return result.isEmpty ? nil : result
        } catch {
            print("⚠️ [WebSessionSummarizer] summarization failed: \(error)")
            return nil
        }
    }

    /// Build the carry-over seed for a fresh session after summarization.
    /// The seed is preamble + goal + structured handoff + continuation
    /// order: the model must pick up the NEXT step, never re-ask what the
    /// summary already establishes.
    static func summarizedSeed(systemPreamble: String,
                               goal: String?,
                               summary: String,
                               restartCount: Int) -> String {
        var parts: [String] = [systemPreamble]
        if let goal, !goal.isEmpty {
            parts.append("Current goal: \(goal)")
        }
        let header = restartCount > 0
            ? "Session #\(restartCount + 1) — previous context summarized:"
            : "Previous context summarized:"
        parts.append("\(header)\n\n\(summary)")
        parts.append("Continue from the NEXT step above using your tools. Do not re-ask for anything the summary already contains; if a tool result you need is missing, re-run that exact tool call.")
        return parts.joined(separator: "\n\n---\n\n")
    }
}
