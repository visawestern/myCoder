import Foundation

/// Conversation compaction: earlier turns are replaced for the MODEL by one
/// factual summary message, while the user keeps the full visible chat.
///
/// The summary is persisted as a real `system` message (DB + feed), so it
/// survives relaunch and re-compaction can merge an older summary instead of
/// rescanning turns that were already dropped.
enum ConversationCompactionLogic {
    /// Prefix that marks a persisted compaction summary. Kept stable: it is
    /// how `historyForModel` finds the newest cut point after reload.
    static let summaryMarker = "[Conversation summary]"

    /// A compaction replaces the whole model-bound history with one summary
    /// message appended at the END of the feed. That keeps DB ordering intact
    /// (rows sort by creation time) — a mid-feed insert would reload *after*
    /// the recent turns and drop them from the model history.
    struct Plan {
        let toSummarize: [Message]
    }

    static func isSummary(_ message: Message) -> Bool {
        message.role == .system && message.content.hasPrefix(summaryMarker)
    }

    /// Model-bound history: everything before the newest summary is dropped.
    static func historyForModel(_ messages: [Message]) -> [Message] {
        guard let index = messages.lastIndex(where: isSummary) else { return messages }
        return Array(messages[index...])
    }

    /// Everything the model would otherwise receive — or nil when a summary
    /// would not preserve any actual dialogue.
    static func plan(messages: [Message]) -> Plan? {
        let history = historyForModel(messages)
        guard history.count >= 2 else { return nil }
        guard history.contains(where: { $0.role == .user || $0.role == .assistant }) else {
            return nil
        }
        return Plan(toSummarize: history)
    }

    static func summaryMessage(summary: String) -> Message {
        Message(
            role: .system,
            content: "\(summaryMarker)\n\(summary)",
            isFinished: true
        )
    }

    /// Plain transcript for the summarizer. Keeps the NEWEST lines when the
    /// budget is exceeded (recent context matters more) and says so explicitly
    /// so the model does not assume the omitted part was empty.
    static func transcript(messages: [Message], maxCharacters: Int = 48_000) -> String {
        var lines: [String] = []
        for message in messages {
            let role: String
            switch message.role {
            case .user: role = "user"
            case .assistant: role = "assistant"
            case .system: role = "system"
            }
            var body = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if body.isEmpty { body = "(empty)" }
            lines.append("\(role): \(body)")
        }

        var selected: [String] = []
        var total = 0
        for line in lines.reversed() {
            let cost = line.count + 1
            if total + cost > maxCharacters, !selected.isEmpty { break }
            selected.append(line)
            total += cost
        }
        selected.reverse()
        let omitted = lines.count - selected.count
        let prefix = omitted > 0 ? "[... \(omitted) earlier messages omitted for length]\n" : ""
        return prefix + selected.joined(separator: "\n")
    }

    static func summaryPrompt(messages: [Message], maxCharacters: Int = 48_000) -> String {
        HarnessPromptQuality.structuralSummaryPrompt(messages: messages, maxCharacters: maxCharacters)
    }

    /// Smallest transcript worth sending — below this the summary request
    /// cannot carry any real context.
    static let minimumSummaryTranscriptCharacters = 2_000

    /// Time budget for one summarization request.
    ///
    /// The transcript is large (tens of thousands of characters), so the
    /// default 120 s of the chat transport is not enough — the request was
    /// killed before the model answered (verified live). The compaction is a
    /// background action the user watches and can stop, so it may take longer.
    static let summaryRequestTimeout: TimeInterval = 300

    /// How many characters of transcript fit into a model window.
    ///
    /// The summary request goes to the model that will continue the chat, so
    /// the transcript must fit into ITS window: a fixed 48k-character
    /// transcript does not fit an 8k model at all. The budget assumes the
    /// worst case (wide characters cost ~1 token each, Latin text ~1/4), and
    /// gives half of the window to the transcript — the rest is the prompt,
    /// the answer and the provider's own overhead.
    ///
    /// An unknown window (0) keeps the default budget.
    static func summaryTranscriptBudget(contextWindowTokens: Int,
                                        defaultCharacters: Int = 48_000) -> Int {
        guard contextWindowTokens > 0 else { return defaultCharacters }
        let transcriptTokens = contextWindowTokens / 2
        let characters = transcriptTokens * 2
        return max(minimumSummaryTranscriptCharacters, min(defaultCharacters, characters))
    }
}

enum ConversationSummarizerError: LocalizedError, Equatable {
    case nothingToCompact
    case emptySummary

    var errorDescription: String? {
        switch self {
        case .nothingToCompact:
            return "The conversation is still short — nothing to compact yet."
        case .emptySummary:
            return "The model returned an empty summary; the context was left unchanged."
        }
    }
}

/// Result of one compaction attempt.
///
/// The outcome is a value, not a chat message: the panel turns it into the
/// visible notice, and the model-switch flow decides from it whether the
/// history was touched. `.cancelled` means the history is EXACTLY as it was —
/// a stopped compaction never appends anything.
enum ConversationCompactionOutcome: Equatable {
    /// The summary (and the human-readable note) were appended to the feed.
    case compacted(summaryMessageID: String, noticeMessageID: String, beforeTokens: Int, afterTokens: Int)
    /// The user stopped the compaction; nothing was appended.
    case cancelled
    /// The summarizer failed; nothing was appended.
    case failed(String)
    /// This provider keeps the history on the server, so a local summary
    /// would not shrink it.
    case unsupported(String)
    /// There was nothing worth compacting.
    case nothingToCompact
}

/// Runs one summarization turn through an injected transport. Keeping the
/// transport a closure makes the service testable without network access and
/// lets the UI supply the route-specific client (direct OpenAI-compatible,
/// OpenCode serve).
struct ConversationSummarizer {
    typealias Transport = (String) async throws -> String

    let transport: Transport

    init(transport: @escaping Transport) {
        self.transport = transport
    }

    /// Summarize the conversation.
    ///
    /// `maxCharacters` bounds the transcript that goes into the request: the
    /// caller knows the window of the model that will continue the chat, and
    /// a transcript that does not fit that window would be rejected.
    func summarize(messages: [Message], maxCharacters: Int = 48_000) async throws -> String {
        // A compaction the user stopped must never produce a summary: the
        // history has to stay exactly as it was.
        try Task.checkCancellation()
        guard let plan = ConversationCompactionLogic.plan(messages: messages) else {
            throw ConversationSummarizerError.nothingToCompact
        }
        let prompt = ConversationCompactionLogic.summaryPrompt(
            messages: plan.toSummarize,
            maxCharacters: maxCharacters
        )
        let raw: String
        do {
            raw = try await transport(prompt)
        } catch {
            // A cancelled request fails with a transport error (the socket was
            // closed). The user stopped it on purpose — report the stop, not
            // the network noise.
            try Task.checkCancellation()
            throw error
        }
        try Task.checkCancellation()
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ConversationSummarizerError.emptySummary }
        return trimmed
    }
}
