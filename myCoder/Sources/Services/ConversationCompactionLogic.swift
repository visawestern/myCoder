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
        """
        You are compacting a coding-assistant conversation so it can continue \
        within a smaller context window. Write a dense factual summary.

        Preserve, when present:
        - the user's goal, constraints and preferences;
        - decisions made and alternatives rejected;
        - files/paths touched and their current state;
        - commands run and their outcomes;
        - errors encountered and how they were fixed;
        - open tasks and next steps.

        Do not invent facts. Do not add commentary about summarizing. \
        Output only the summary as Markdown bullet points (max 400 words).

        Conversation:
        \(transcript(messages: messages, maxCharacters: maxCharacters))
        """
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

/// Runs one summarization turn through an injected transport. Keeping the
/// transport a closure makes the service testable without network access and
/// lets the UI supply the route-specific client (direct OpenAI-compatible,
/// OpenCode serve, or myCoder Auto Free).
struct ConversationSummarizer {
    typealias Transport = (String) async throws -> String

    let transport: Transport

    init(transport: @escaping Transport) {
        self.transport = transport
    }

    func summarize(messages: [Message]) async throws -> String {
        guard let plan = ConversationCompactionLogic.plan(messages: messages) else {
            throw ConversationSummarizerError.nothingToCompact
        }
        let prompt = ConversationCompactionLogic.summaryPrompt(messages: plan.toSummarize)
        let raw = try await transport(prompt)
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ConversationSummarizerError.emptySummary }
        return trimmed
    }
}
