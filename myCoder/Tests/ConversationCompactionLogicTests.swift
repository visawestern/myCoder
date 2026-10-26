import Testing
import Foundation
@testable import myCoder

/// Compaction keeps the conversation usable inside a smaller window: earlier
/// turns are replaced for the model by one factual summary, while the user
/// still sees the full chat.
@Suite("Conversation compaction")
struct ConversationCompactionLogicTests {

    private func message(_ role: MessageRole, _ content: String) -> Message {
        Message(role: role, content: content, isFinished: true)
    }

    private func conversation(_ count: Int) -> [Message] {
        (0..<count).map { i in
            message(i % 2 == 0 ? .user : .assistant, "turn \(i) payload")
        }
    }

    @Test func cannotCompactTinyConversation() {
        #expect(ConversationCompactionLogic.plan(messages: []) == nil)
        #expect(ConversationCompactionLogic.plan(messages: conversation(1)) == nil)
    }

    @Test func planSummarizesWholeModelHistory() {
        let plan = ConversationCompactionLogic.plan(messages: conversation(20))
        #expect(plan?.toSummarize.count == 20)
    }

    @Test func summaryMarkerIsDetectableAndSystemScoped() {
        let summary = ConversationCompactionLogic.summaryMessage(summary: "- user wants X")
        #expect(summary.role == .system)
        #expect(ConversationCompactionLogic.isSummary(summary))
        #expect(summary.content.contains("- user wants X"))
    }

    @Test func historyForModelStartsAtLastSummary() {
        let summary = ConversationCompactionLogic.summaryMessage(summary: "- prior work")
        let messages = [
            message(.user, "old question"),
            message(.assistant, "old answer"),
            summary,
            message(.user, "new question"),
            message(.assistant, "new answer"),
        ]
        let history = ConversationCompactionLogic.historyForModel(messages)
        #expect(history.count == 3)
        #expect(history.first.map(ConversationCompactionLogic.isSummary) == true)
        #expect(history.last?.content == "new answer")
    }

    @Test func historyWithoutSummaryIsUnchanged() {
        let messages = conversation(4)
        #expect(ConversationCompactionLogic.historyForModel(messages).count == 4)
    }

    @Test func recompactionIgnoresPreSummaryTurns() {
        let summary = ConversationCompactionLogic.summaryMessage(summary: "- prior")
        var messages: [Message] = [message(.user, "ancient"), summary]
        messages += conversation(12)
        let plan = ConversationCompactionLogic.plan(messages: messages)
        #expect(plan?.toSummarize.count == 13)
        #expect(plan?.toSummarize.contains(where: { $0.content == "ancient" }) == false)
        #expect(plan?.toSummarize.contains(where: ConversationCompactionLogic.isSummary) == true)
    }

    @Test func transcriptLabelsRolesAndKeepsNewestWhenCapped() {
        let messages = [
            message(.user, "OLDEST-MARKER " + String(repeating: "x", count: 100)),
            message(.assistant, "middle " + String(repeating: "y", count: 100)),
            message(.user, "NEWEST-MARKER"),
        ]
        let transcript = ConversationCompactionLogic.transcript(messages: messages, maxCharacters: 160)
        #expect(transcript.contains("NEWEST-MARKER"))
        #expect(!transcript.contains("OLDEST-MARKER"))
        #expect(transcript.contains("user:"))
        #expect(transcript.contains("assistant:"))
    }

    @Test func promptDemandsFactsWithoutInvention() {
        let prompt = ConversationCompactionLogic.summaryPrompt(
            messages: [message(.user, "fix the login bug")], maxCharacters: 10_000
        )
        #expect(prompt.lowercased().contains("do not invent"))
        #expect(prompt.contains("fix the login bug"))
        #expect(prompt.lowercased().contains("files"))
        #expect(prompt.lowercased().contains("next steps"))
    }

    @Test func summarizerRejectsEmptyTransportOutput() async {
        let summarizer = ConversationSummarizer(transport: { _ in "   " })
        await #expect(throws: ConversationSummarizerError.emptySummary) {
            _ = try await summarizer.summarize(messages: conversation(20))
        }
    }

    @Test func summarizerThrowsWhenNothingToCompact() async {
        let summarizer = ConversationSummarizer(transport: { _ in "unused" })
        await #expect(throws: ConversationSummarizerError.nothingToCompact) {
            _ = try await summarizer.summarize(messages: [])
        }
    }

    @Test func summarizerSendsPromptAndTrimsResult() async throws {
        let summarizer = ConversationSummarizer(transport: { prompt in
            #expect(prompt.contains("turn 0 payload"))
            return "  - summary line  \n"
        })
        let summary = try await summarizer.summarize(messages: conversation(20))
        #expect(summary == "- summary line")
    }
}
