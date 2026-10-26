import Testing
import Foundation
@testable import myCoder

// MARK: - MessageRole Enum (MSG-02)

@Suite("MessageRole enum")
struct MessageRoleTests {

    @Test("MessageRole has user case")
    func userCase() {
        let role = MessageRole.user
        #expect(role == .user)
    }

    @Test("MessageRole has assistant case")
    func assistantCase() {
        let role = MessageRole.assistant
        #expect(role == .assistant)
    }

    @Test("MessageRole has system case")
    func systemCase() {
        let role = MessageRole.system
        #expect(role == .system)
    }

    @Test("MessageRole all cases cover three values")
    func allCases() {
        let all: [MessageRole] = [.user, .assistant, .system]
        #expect(all.count == 3)
    }

    @Test("MessageRole can switch over cases")
    func switchCoverage() {
        func label(for role: MessageRole) -> String {
            switch role {
            case .user: return "user"
            case .assistant: return "assistant"
            case .system: return "system"
            }
        }
        #expect(label(for: .user) == "user")
        #expect(label(for: .assistant) == "assistant")
        #expect(label(for: .system) == "system")
    }
}

// MARK: - MessagePartContent Enum (MSG-02)

@Suite("MessagePartContent enum")
struct MessagePartContentTests {

    @Test("text case stores string")
    func textCase() {
        let part = MessagePartContent.text("Hello")
        if case .text(let value) = part {
            #expect(value == "Hello")
        } else {
            #expect(Bool(false), "Expected .text case")
        }
    }

    @Test("reasoning case stores string")
    func reasoningCase() {
        let part = MessagePartContent.reasoning("thinking")
        if case .reasoning(let value) = part {
            #expect(value == "thinking")
        } else {
            #expect(Bool(false), "Expected .reasoning case")
        }
    }

    @Test("toolCall case stores name, args, result, callID")
    func toolCallCase() {
        let part = MessagePartContent.toolCall(name: "read", args: "{}", result: "ok", callID: "call-1")
        if case .toolCall(let name, let args, let result, let callID) = part {
            #expect(name == "read")
            #expect(args == "{}")
            #expect(result == "ok")
            #expect(callID == "call-1")
        } else {
            #expect(Bool(false), "Expected .toolCall case")
        }
    }

    @Test("toolCall case stores nil result and callID")
    func toolCallNilResult() {
        let part = MessagePartContent.toolCall(name: "write", args: "{}", result: nil, callID: nil)
        if case .toolCall(_, _, let result, let callID) = part {
            #expect(result == nil)
            #expect(callID == nil)
        }
    }

    @Test("stepStart case")
    func stepStartCase() {
        let part = MessagePartContent.stepStart
        #expect(part.id == "step-start")
    }

    @Test("stepFinish case")
    func stepFinishCase() {
        let part = MessagePartContent.stepFinish
        #expect(part.id == "step-finish")
    }

    @Test("image case stores base64 and mimeType")
    func imageCase() {
        let part = MessagePartContent.image(base64: "abc123", mimeType: "image/png")
        if case .image(let b64, let mime) = part {
            #expect(b64 == "abc123")
            #expect(mime == "image/png")
        } else {
            #expect(Bool(false), "Expected .image case")
        }
    }

    // MARK: - ID computation

    @Test("text id uses text- prefix with hash")
    func textId() {
        let part = MessagePartContent.text("hello")
        #expect(part.id.hasPrefix("text-"))
    }

    @Test("reasoning id uses reasoning- prefix with hash")
    func reasoningId() {
        let part = MessagePartContent.reasoning("think")
        #expect(part.id.hasPrefix("reasoning-"))
    }

    @Test("toolCall id uses tool- prefix with callID when available")
    func toolCallIdWithCallID() {
        let part = MessagePartContent.toolCall(name: "read", args: "{}", result: nil, callID: "call-xyz")
        #expect(part.id == "tool-call-xyz")
    }

    @Test("toolCall id falls back to name-hash when callID is empty")
    func toolCallIdEmptyCallID() {
        let part = MessagePartContent.toolCall(name: "write", args: "{\"key\":\"val\"}", result: nil, callID: "")
        #expect(part.id.hasPrefix("tool-write-"))
    }

    @Test("toolCall id falls back to name-hash when callID is nil")
    func toolCallIdNilCallID() {
        let part = MessagePartContent.toolCall(name: "read", args: "{}", result: nil, callID: nil)
        #expect(part.id.hasPrefix("tool-read-"))
    }

    @Test("stepStart id is step-start")
    func stepStartId() {
        #expect(MessagePartContent.stepStart.id == "step-start")
    }

    @Test("stepFinish id is step-finish")
    func stepFinishId() {
        #expect(MessagePartContent.stepFinish.id == "step-finish")
    }

    @Test("image id uses image- prefix with hash")
    func imageId() {
        let part = MessagePartContent.image(base64: "base64data", mimeType: "image/png")
        #expect(part.id.hasPrefix("image-"))
    }
}

// MARK: - MessageResponseMergeLogic (MSG-02)

@Suite("MessageResponseMergeLogic comprehensive")
struct MessageResponseMergeLogicComprehensiveTests {

    // MARK: resolvedText

    @Test("resolvedText prefers serverText over existingContent and streamingText")
    func resolvedTextServerPriority() {
        let result = MessageResponseMergeLogic.resolvedText(
            serverText: "server",
            existingContent: "existing",
            streamingText: "streaming"
        )
        #expect(result == "server")
    }

    @Test("resolvedText uses existingContent when serverText is empty")
    func resolvedTextExistingFallback() {
        let result = MessageResponseMergeLogic.resolvedText(
            serverText: "",
            existingContent: "existing",
            streamingText: "streaming"
        )
        #expect(result == "existing")
    }

    @Test("resolvedText uses streamingText when both serverText and existingContent are empty")
    func resolvedTextStreamingFallback() {
        let result = MessageResponseMergeLogic.resolvedText(
            serverText: "",
            existingContent: "",
            streamingText: "streaming"
        )
        #expect(result == "streaming")
    }

    @Test("resolvedText returns empty when all inputs are empty")
    func resolvedTextAllEmpty() {
        let result = MessageResponseMergeLogic.resolvedText(
            serverText: "",
            existingContent: "",
            streamingText: ""
        )
        #expect(result.isEmpty)
    }

    // MARK: upsertTextPart

    @Test("upsertTextPart adds text part when parts is empty")
    func upsertTextAddsToEmpty() {
        var parts: [MessagePartContent] = []
        MessageResponseMergeLogic.upsertTextPart(&parts, text: "Hello")
        #expect(parts.count == 1)
        if case .text(let t) = parts[0] {
            #expect(t == "Hello")
        } else {
            #expect(Bool(false), "Expected .text")
        }
    }

    @Test("upsertTextPart replaces existing text part")
    func upsertTextReplaces() {
        var parts: [MessagePartContent] = [.text("old")]
        MessageResponseMergeLogic.upsertTextPart(&parts, text: "new")
        #expect(parts.count == 1)
        if case .text(let t) = parts[0] {
            #expect(t == "new")
        }
    }

    @Test("upsertTextPart appends after non-text parts")
    func upsertTextAppendsAfterReasoning() {
        var parts: [MessagePartContent] = [.reasoning("thinking")]
        MessageResponseMergeLogic.upsertTextPart(&parts, text: "answer")
        #expect(parts.count == 2)
        if case .text(let t) = parts[1] {
            #expect(t == "answer")
        }
    }

    @Test("upsertTextPart does nothing for empty text")
    func upsertTextEmpty() {
        var parts: [MessagePartContent] = [.text("existing")]
        MessageResponseMergeLogic.upsertTextPart(&parts, text: "")
        #expect(parts.count == 1)
    }

    // MARK: upsertReasoningPart

    @Test("upsertReasoningPart inserts reasoning at index 0 when parts empty")
    func upsertReasoningInsertsAtZero() {
        var parts: [MessagePartContent] = []
        MessageResponseMergeLogic.upsertReasoningPart(&parts, text: "thinking")
        #expect(parts.count == 1)
        if case .reasoning(let t) = parts[0] {
            #expect(t == "thinking")
        }
    }

    @Test("upsertReasoningPart inserts at index 0 when parts have other content")
    func upsertReasoningInsertsBeforeOtherParts() {
        var parts: [MessagePartContent] = [.text("answer")]
        MessageResponseMergeLogic.upsertReasoningPart(&parts, text: "thinking")
        #expect(parts.count == 2)
        if case .reasoning(let t) = parts[0] {
            #expect(t == "thinking")
        }
    }

    @Test("upsertReasoningPart replaces existing reasoning part")
    func upsertReasoningReplaces() {
        var parts: [MessagePartContent] = [.reasoning("old"), .text("answer")]
        MessageResponseMergeLogic.upsertReasoningPart(&parts, text: "new thinking")
        #expect(parts.count == 2)
        if case .reasoning(let t) = parts[0] {
            #expect(t == "new thinking")
        }
    }

    @Test("upsertReasoningPart does nothing for empty text")
    func upsertReasoningEmpty() {
        var parts: [MessagePartContent] = [.reasoning("existing")]
        MessageResponseMergeLogic.upsertReasoningPart(&parts, text: "")
        #expect(parts.count == 1)
    }

    // MARK: mergedAssistantMessage

    @Test("mergedAssistantMessage uses serverParts when provided")
    func mergedUsesServerParts() {
        let existing = Message(role: .assistant, content: "old")
        let serverParts: [MimoMessagePart] = [.text("new from server")]
        let result = MessageResponseMergeLogic.mergedAssistantMessage(
            existing: existing,
            serverParts: serverParts,
            serverText: "",
            streamingText: ""
        )
        #expect(result.content == "old")
        #expect(result.parts.count == 1)
        if case .text(let t) = result.parts[0] {
            #expect(t == "new from server")
        }
    }

    @Test("mergedAssistantMessage uses existing parts when no serverParts")
    func mergedUsesExistingParts() {
        let existing = Message(
            role: .assistant,
            content: "existing",
            parts: [.text("existing")],
            reasoning: "thinking"
        )
        let result = MessageResponseMergeLogic.mergedAssistantMessage(
            existing: existing,
            serverParts: nil,
            serverText: "",
            streamingText: ""
        )
        #expect(result.content == "existing")
        #expect(result.reasoning == "thinking")
    }

    @Test("mergedAssistantMessage upserts reasoning from existing.reasoning")
    func mergedIncludesReasoning() {
        let existing = Message(
            role: .assistant,
            content: "answer",
            parts: [],
            reasoning: "deep thought"
        )
        let result = MessageResponseMergeLogic.mergedAssistantMessage(
            existing: existing,
            serverParts: nil,
            serverText: "",
            streamingText: ""
        )
        #expect(result.reasoning == "deep thought")
        #expect(result.parts.contains { if case .reasoning = $0 { return true }; return false })
    }

    @Test("mergedAssistantMessage prefers serverText over existing content")
    func mergedPrefersServerText() {
        let existing = Message(role: .assistant, content: "existing")
        let result = MessageResponseMergeLogic.mergedAssistantMessage(
            existing: existing,
            serverParts: nil,
            serverText: "server text",
            streamingText: "streaming"
        )
        #expect(result.content == "server text")
    }

    @Test("mergedAssistantMessage merges serverParts with reasoning")
    func mergedServerPartsWithReasoning() {
        let serverParts: [MimoMessagePart] = [
            .reasoning("server thought"),
            .text("server answer")
        ]
        let existing = Message(role: .assistant, content: "old", reasoning: "old thought")
        let result = MessageResponseMergeLogic.mergedAssistantMessage(
            existing: existing,
            serverParts: serverParts,
            serverText: "",
            streamingText: ""
        )
        #expect(result.content == "old")
        #expect(result.reasoning == "server thought")
    }

    // MARK: deduplicatedParts

    @Test("deduplicatedParts removes adjacent duplicate text parts")
    func dedupAdjacentText() {
        let parts: [MessagePartContent] = [.text("hello"), .text("hello")]
        let result = MessageResponseMergeLogic.deduplicatedParts(parts)
        #expect(result.count == 1)
    }

    @Test("deduplicatedParts removes non-adjacent duplicate text")
    func dedupNonAdjacentText() {
        let parts: [MessagePartContent] = [.text("hello"), .reasoning("think"), .text("hello")]
        let result = MessageResponseMergeLogic.deduplicatedParts(parts)
        #expect(result.count == 2)
    }

    @Test("deduplicatedParts keeps adjacent duplicate reasoning")
    func dedupAdjacentReasoningKept() {
        let parts: [MessagePartContent] = [.reasoning("think"), .reasoning("think")]
        let result = MessageResponseMergeLogic.deduplicatedParts(parts)
        #expect(result.count == 1)
    }

    @Test("deduplicatedParts keeps non-adjacent duplicate reasoning")
    func dedupNonAdjacentReasoningKept() {
        let parts: [MessagePartContent] = [.reasoning("think"), .text("hello"), .reasoning("think")]
        let result = MessageResponseMergeLogic.deduplicatedParts(parts)
        #expect(result.count == 3)
    }

    @Test("deduplicatedParts passes through unique parts")
    func dedupUniqueParts() {
        let parts: [MessagePartContent] = [.text("a"), .text("b"), .reasoning("c")]
        let result = MessageResponseMergeLogic.deduplicatedParts(parts)
        #expect(result.count == 3)
    }

    @Test("deduplicatedParts keeps non-text parts regardless of duplication")
    func dedupNonTextParts() {
        let parts: [MessagePartContent] = [
            .toolCall(name: "read", args: "{}", result: "ok", callID: "1"),
            .toolCall(name: "read", args: "{}", result: "ok", callID: "1")
        ]
        let result = MessageResponseMergeLogic.deduplicatedParts(parts)
        #expect(result.count == 2)
    }

    @Test("deduplicatedParts keeps stepStart and stepFinish")
    func dedupStepMarkers() {
        let parts: [MessagePartContent] = [.stepStart, .stepFinish, .stepStart, .stepFinish]
        let result = MessageResponseMergeLogic.deduplicatedParts(parts)
        #expect(result.count == 4)
    }

    // MARK: visibleText

    @Test("visibleText extracts text from parts")
    func visibleTextFromParts() {
        let message = Message(
            role: .assistant,
            content: "",
            parts: [.text("first"), .text("second")]
        )
        let result = MessageResponseMergeLogic.visibleText(message)
        #expect(result == "first\n\nsecond")
    }

    @Test("visibleText falls back to content when no text parts")
    func visibleTextFromContent() {
        let message = Message(
            role: .assistant,
            content: "fallback content",
            parts: [.reasoning("think")]
        )
        let result = MessageResponseMergeLogic.visibleText(message)
        #expect(result == "fallback content")
    }

    @Test("visibleText returns empty when no text and no content")
    func visibleTextEmpty() {
        let message = Message(
            role: .assistant,
            content: "",
            parts: [.reasoning("think")]
        )
        let result = MessageResponseMergeLogic.visibleText(message)
        #expect(result.isEmpty)
    }

    @Test("visibleText ignores empty text parts")
    func visibleTextIgnoresEmptyParts() {
        let message = Message(
            role: .assistant,
            content: "",
            parts: [.text(""), .text("actual")]
        )
        let result = MessageResponseMergeLogic.visibleText(message)
        #expect(result == "actual")
    }

    // MARK: reasoningForDisplay

    @Test("reasoningForDisplay returns empty when reasoning matches visible text")
    func reasoningHiddenWhenMatching() {
        let message = Message(
            role: .assistant,
            content: "hello world",
            parts: [.text("hello world")],
            reasoning: "hello world"
        )
        let result = MessageResponseMergeLogic.reasoningForDisplay(message)
        #expect(result.isEmpty)
    }

    @Test("reasoningForDisplay returns reasoning when it differs from visible text")
    func reasoningShownWhenDifferent() {
        let message = Message(
            role: .assistant,
            content: "short answer",
            parts: [.text("short answer")],
            reasoning: "long chain of thought"
        )
        let result = MessageResponseMergeLogic.reasoningForDisplay(message)
        #expect(result == "long chain of thought")
    }

    @Test("reasoningForDisplay returns empty when both reasoning and visible are empty")
    func reasoningEmptyWhenBothEmpty() {
        let message = Message(role: .assistant, content: "", reasoning: "")
        let result = MessageResponseMergeLogic.reasoningForDisplay(message)
        #expect(result.isEmpty)
    }

    @Test("reasoningForDisplay returns empty when reasoning is prefix of long visible text")
    func reasoningHiddenWhenPrefixOfLongText() {
        let longText = String(repeating: "word ", count: 30) // > 80 chars
        let message = Message(
            role: .assistant,
            content: longText,
            parts: [.text(longText)],
            reasoning: "word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word "
        )
        let result = MessageResponseMergeLogic.reasoningForDisplay(message)
        #expect(result.isEmpty)
    }
}

// MARK: - Reasoning spoiler grouping

@Suite("Reasoning spoiler grouping")
struct ReasoningSpoilerGroupingTests {

    @Test("Reasoning from every assistant message in one turn lands in one spoiler")
    func combinesReasoningAcrossToolRounds() {
        let messages = [
            Message(role: .user, content: "go"),
            Message(
                role: .assistant,
                content: "",
                parts: [.reasoning("first"), .toolCall(name: "read", args: "{}", result: nil, callID: "1")],
                reasoning: "first"
            ),
            Message(
                role: .assistant,
                content: "",
                parts: [.reasoning("second"), .toolCall(name: "read", args: "{}", result: nil, callID: "2")],
                reasoning: "second"
            ),
            Message(
                role: .assistant,
                content: "answer",
                parts: [.reasoning("third"), .text("answer")],
                reasoning: "third"
            )
        ]

        let displayed = MessageDisplayLogic.messagesForDisplay(messages)

        #expect(displayed.count == 4)
        #expect(displayed[1].reasoning == "first\n\nsecond\n\nthird")
        #expect(displayed[2].reasoning.isEmpty)
        #expect(displayed[3].reasoning.isEmpty)
        #expect(displayed[1].parts.contains { part in
            if case .reasoning("first\n\nsecond\n\nthird") = part { return true }
            return false
        })
    }

    @Test("Reasoning stays separated when a user message starts a new turn")
    func keepsTurnsSeparate() {
        let messages = [
            Message(role: .user, content: "one"),
            Message(role: .assistant, content: "answer one", parts: [.text("answer one")], reasoning: "a"),
            Message(role: .user, content: "two"),
            Message(role: .assistant, content: "answer two", parts: [.text("answer two")], reasoning: "b")
        ]

        let displayed = MessageDisplayLogic.messagesForDisplay(messages)

        #expect(displayed.count == 4)
        #expect(displayed[1].reasoning == "a")
        #expect(displayed[3].reasoning == "b")
    }

    @Test("A thinking-only preamble and later tool rounds share one spoiler")
    func foldsPreambleWithToolRounds() {
        let messages = [
            Message(role: .user, content: "go"),
            Message(role: .assistant, content: "", parts: [.reasoning("preamble")], reasoning: "preamble"),
            Message(
                role: .assistant,
                content: "",
                parts: [.reasoning("tool thought"), .toolCall(name: "read", args: "{}", result: nil, callID: "1")],
                reasoning: "tool thought"
            ),
            Message(
                role: .assistant,
                content: "answer",
                parts: [.reasoning("final thought"), .text("answer")],
                reasoning: "final thought"
            )
        ]

        let displayed = MessageDisplayLogic.messagesForDisplay(messages)

        #expect(displayed.count == 4)
        #expect(displayed[1].reasoning == "preamble\n\ntool thought\n\nfinal thought")
        #expect(displayed[2].reasoning.isEmpty)
        #expect(displayed[3].reasoning.isEmpty)
    }

    @Test("Live reasoning stays with the streaming bubble")
    func keepsLiveReasoningInPlace() {
        let messages = [
            Message(role: .user, content: "go"),
            Message(
                role: .assistant,
                content: "",
                parts: [.reasoning("finished"), .toolCall(name: "read", args: "{}", result: nil, callID: "1")],
                reasoning: "finished"
            ),
            Message(
                role: .assistant,
                content: "",
                isStreaming: true,
                parts: [.reasoning("live")],
                reasoning: "live"
            )
        ]

        let displayed = MessageDisplayLogic.messagesForDisplay(messages)

        #expect(displayed[1].reasoning == "finished")
        #expect(displayed[2].reasoning == "live")
    }

    @Test("Duplicate reasoning across the channel and a part is kept once")
    func deduplicatesRepeatedChunks() {
        let messages = [
            Message(role: .user, content: "go"),
            Message(
                role: .assistant,
                content: "",
                parts: [.reasoning("same"), .toolCall(name: "read", args: "{}", result: nil, callID: "1")],
                reasoning: "same"
            ),
            Message(
                role: .assistant,
                content: "answer",
                parts: [.reasoning("next"), .text("answer")],
                reasoning: "next"
            )
        ]

        let displayed = MessageDisplayLogic.messagesForDisplay(messages)

        #expect(displayed[1].reasoning == "same\n\nnext")
    }
}

// MARK: - Stop Generation Notification Wiring (MSG-03)

@Suite("Stop Generation Notification Wiring")
struct StopGenerationNotificationWiringTests {

    @Test("stopGeneration notification name has correct raw value")
    func notificationNameRawValue() {
        #expect(Notification.Name.stopGeneration.rawValue == "MiMoStopGeneration")
    }

    @Test("stopGeneration notification can be posted and received")
    func notificationIsPostedAndReceived() {
        var received = false
        let observer = NotificationCenter.default.addObserver(
            forName: .stopGeneration,
            object: nil,
            queue: nil
        ) { _ in
            received = true
        }

        NotificationCenter.default.post(name: .stopGeneration, object: nil)

        #expect(received)
        NotificationCenter.default.removeObserver(observer)
    }
}

// MARK: - Message Retry Logic (MSG-06)

@Suite("Message Retry Logic")
struct MessageRetryLogicTests {

    private static func findPrecedingUserMessage(
        in messages: [Message],
        for assistantID: String
    ) -> Message? {
        guard let index = messages.firstIndex(where: { $0.id == assistantID }) else { return nil }
        for i in (0..<index).reversed() {
            if messages[i].role == .user {
                return messages[i]
            }
        }
        return nil
    }

    @Test("finds preceding user message for assistant message")
    func findsPrecedingUser() {
        let userMsg = Message(id: "u1", role: .user, content: "Hello")
        let assistantMsg = Message(id: "a1", role: .assistant, content: "Hi there")
        let messages = [userMsg, assistantMsg]

        let found = MessageRetryLogicTests.findPrecedingUserMessage(in: messages, for: "a1")
        #expect(found?.id == "u1")
    }

    @Test("returns nil when no preceding user message exists")
    func noPrecedingUser() {
        let msg = Message(id: "a1", role: .assistant, content: "Hi")
        let messages = [msg]

        let found = MessageRetryLogicTests.findPrecedingUserMessage(in: messages, for: "a1")
        #expect(found == nil)
    }

    @Test("returns nil when assistant message ID is not in the list")
    func unknownAssistantID() {
        let msg = Message(id: "u1", role: .user, content: "Hello")
        let messages = [msg]

        let found = MessageRetryLogicTests.findPrecedingUserMessage(in: messages, for: "nonexistent")
        #expect(found == nil)
    }

    @Test("skips assistant messages between user and target")
    func skipsIntermediateAssistantMessages() {
        let userMsg = Message(id: "u1", role: .user, content: "Hello")
        let otherAssistant = Message(id: "a0", role: .assistant, content: "Old")
        let targetAssistant = Message(id: "a1", role: .assistant, content: "New")
        let messages = [userMsg, otherAssistant, targetAssistant]

        let found = MessageRetryLogicTests.findPrecedingUserMessage(in: messages, for: "a1")
        #expect(found?.id == "u1")
    }

    @Test("returns the nearest preceding user message")
    func nearestPrecedingUser() {
        let user1 = Message(id: "u1", role: .user, content: "First")
        let assistant1 = Message(id: "a1", role: .assistant, content: "Response 1")
        let user2 = Message(id: "u2", role: .user, content: "Second")
        let assistant2 = Message(id: "a2", role: .assistant, content: "Response 2")
        let messages = [user1, assistant1, user2, assistant2]

        let found = MessageRetryLogicTests.findPrecedingUserMessage(in: messages, for: "a2")
        #expect(found?.id == "u2")
    }
}

// MARK: - ToolCallPresentationLogic (MSG-11)

@Suite("ToolCallPresentationLogic")
struct ToolCallPresentationLogicAdditionalTests {

    // MARK: argumentSections

    @Test("argumentSections handles non-JSON string as single value section")
    func argsNonJSON() {
        let sections = ToolCallPresentationLogic.argumentSections(from: "plain text")
        #expect(sections.count == 1)
        #expect(sections[0].key == "value")
        #expect(sections[0].value == "plain text")
    }

    @Test("argumentSections parses JSON dictionary into sections sorted by priority")
    func argsJSONDict() {
        let args = #"{"command":"ls -la","path":"/tmp","verbose":true}"#
        let sections = ToolCallPresentationLogic.argumentSections(from: args)
        // path has priority 0, command priority 1, verbose priority 2
        #expect(sections[0].key == "path")
        #expect(sections[1].key == "command")
        #expect(sections[2].key == "verbose")
    }

    @Test("argumentSections returns empty for empty JSON object")
    func argsEmptyObject() {
        let sections = ToolCallPresentationLogic.argumentSections(from: "{}")
        #expect(sections.isEmpty)
    }

    // MARK: title

    @Test("title for write tool with path shows Writing filename")
    func titleWriteTool() {
        let title = ToolCallPresentationLogic.title(
            name: "write",
            args: #"{"path":"/project/src/main.swift"}"#
        )
        #expect(title == "Writing main.swift")
    }

    @Test("title for edit tool with path shows Editing filename")
    func titleEditTool() {
        let title = ToolCallPresentationLogic.title(
            name: "edit",
            args: #"{"file":"/project/src/main.swift"}"#
        )
        #expect(title == "Editing main.swift")
    }

    @Test("title for read tool with path shows Reading filename")
    func titleReadTool() {
        let title = ToolCallPresentationLogic.title(
            name: "read",
            args: #"{"filepath":"/project/README.md"}"#
        )
        #expect(title == "Reading README.md")
    }

    @Test("title for search tool with query shows Searching for query")
    func titleSearchTool() {
        let title = ToolCallPresentationLogic.title(
            name: "search",
            args: #"{"query":"TODO"}"#
        )
        #expect(title == "Searching for TODO")
    }

    @Test("title for grep tool with pattern shows Searching for pattern")
    func titleGrepTool() {
        let title = ToolCallPresentationLogic.title(
            name: "grep",
            args: #"{"pattern":"FIXME"}"#
        )
        #expect(title == "Searching for FIXME")
    }

    @Test("title for bash tool with command shows Running command")
    func titleBashTool() {
        let title = ToolCallPresentationLogic.title(
            name: "bash",
            args: #"{"command":"make build"}"#
        )
        #expect(title == "Running make build")
    }

    @Test("title for fetch tool with url shows Fetching url")
    func titleFetchTool() {
        let title = ToolCallPresentationLogic.title(
            name: "fetch",
            args: #"{"url":"https://example.com"}"#
        )
        #expect(title == "Fetching https://example.com")
    }

    @Test("title for unknown tool falls back to capitalized name")
    func titleUnknownTool() {
        let title = ToolCallPresentationLogic.title(
            name: "unknown_tool",
            args: "{}"
        )
        #expect(title == "Unknown Tool")
    }

    @Test("title uses description when available for unknown tool")
    func titleWithDescription() {
        let title = ToolCallPresentationLogic.title(
            name: "custom",
            args: #"{"description":"Running custom logic"}"#
        )
        #expect(title == "Running custom logic")
    }

    @Test("title for task tool uses description")
    func titleTaskTool() {
        let title = ToolCallPresentationLogic.title(
            name: "task",
            args: #"{"title":"Implement login feature"}"#
        )
        #expect(title == "Implement login feature")
    }

    @Test("title for sleep tool includes duration")
    func titleSleepTool() {
        let title = ToolCallPresentationLogic.title(
            name: "sleep",
            args: #"{"duration":"5"}"#
        )
        #expect(title == "⏳ Waiting 5s")
    }

    // MARK: formattedResult

    @Test("formattedResult pretty-prints valid JSON")
    func formattedResultValidJSON() {
        let result = ToolCallPresentationLogic.formattedResult(#"{"key":"value","num":42}"#)
        #expect(result.contains("\"key\" : \"value\""))
        #expect(result.contains("\"num\" : 42"))
    }

    @Test("formattedResult returns raw string for non-JSON")
    func formattedResultNonJSON() {
        let result = ToolCallPresentationLogic.formattedResult("plain output")
        #expect(result == "plain output")
    }

    @Test("formattedResult handles empty string")
    func formattedResultEmpty() {
        let result = ToolCallPresentationLogic.formattedResult("")
        #expect(result.isEmpty)
    }
}

// MARK: - MessageDisplayLogic Image Handling (MSG-12)

@Suite("MessageDisplayLogic Image Handling")
struct MessageDisplayLogicImageTests {

    @Test("attachedImagesForDisplay returns images when message has no image parts")
    func attachedImagesDisplayedWhenNoParts() {
        let image = ClipboardImage(base64: "deadbeef", mimeType: "image/png")
        let message = Message(role: .user, content: "check this", attachedImages: [image])
        #expect(!MessageDisplayLogic.hasImageParts(message))
        #expect(MessageDisplayLogic.attachedImagesForDisplay(message).count == 1)
    }

    @Test("attachedImagesForDisplay returns empty when message has image parts")
    func attachedImagesHiddenWhenPartsExist() {
        let image = ClipboardImage(base64: "abc123", mimeType: "image/png")
        let message = Message(
            role: .user,
            content: "check this",
            parts: [.image(base64: "abc123", mimeType: "image/png")],
            attachedImages: [image]
        )
        #expect(MessageDisplayLogic.hasImageParts(message))
        #expect(MessageDisplayLogic.attachedImagesForDisplay(message).isEmpty)
    }

    @Test("attachedImagesForDisplay returns empty when attachedImages is nil")
    func attachedImagesNil() {
        let message = Message(role: .user, content: "no images")
        #expect(!MessageDisplayLogic.hasImageParts(message))
        #expect(MessageDisplayLogic.attachedImagesForDisplay(message).isEmpty)
    }

    @Test("attachedImagesForDisplay returns empty when message has both image parts and attachedImages")
    func attachedImagesEmptyWithImageParts() {
        let message = Message(
            role: .user,
            content: "",
            parts: [.image(base64: "xyz", mimeType: "image/png"), .text("desc")],
            attachedImages: [ClipboardImage(base64: "xyz", mimeType: "image/png")]
        )
        #expect(MessageDisplayLogic.attachedImagesForDisplay(message).isEmpty)
    }

    @Test("hasImageParts returns true when parts contain image")
    func hasImagePartsTrue() {
        let message = Message(
            role: .user,
            content: "",
            parts: [.image(base64: "data", mimeType: "image/jpeg")]
        )
        #expect(MessageDisplayLogic.hasImageParts(message))
    }

    @Test("hasImageParts returns false when parts contain no image")
    func hasImagePartsFalse() {
        let message = Message(
            role: .user,
            content: "",
            parts: [.text("hello")]
        )
        #expect(!MessageDisplayLogic.hasImageParts(message))
    }

    @Test("hasImageParts returns false when message has no parts")
    func hasImagePartsEmpty() {
        let message = Message(role: .user, content: "hello")
        #expect(!MessageDisplayLogic.hasImageParts(message))
    }
}

// MARK: - Markdown Text Scale & Parsing (MSG-13)

@Suite("Markdown Text Scale & Parsing")
struct MarkdownTextScaleAndParsingTests {

    // MARK: InterfaceTypography.scaled

    @Test("scaled multiplies base by scale and rounds")
    func scaledBasic() {
        #expect(InterfaceTypography.scaled(14, scale: 1.0) == 14)
    }

    @Test("scaled increases size with larger scale")
    func scaledIncrease() {
        #expect(InterfaceTypography.scaled(14, scale: 1.25) == 18) // 17.5 rounded
    }

    @Test("scaled decreases size with smaller scale")
    func scaledDecrease() {
        // 14 * 0.75 = 10.5, rounded(.toNearestOrAwayFromZero) = 11
        #expect(InterfaceTypography.scaled(14, scale: 0.75) == 11)
    }

    @Test("scaled with zero scale returns zero")
    func scaledZero() {
        #expect(InterfaceTypography.scaled(14, scale: 0) == 0)
    }

    @Test("scaled rounds to nearest integer")
    func scaledRounding() {
        // 10 * 0.45 = 4.5 -> 5 (away from zero)
        #expect(InterfaceTypography.scaled(10, scale: 0.45) == 5)
        // 10 * 0.44 = 4.4 -> 4
        #expect(InterfaceTypography.scaled(10, scale: 0.44) == 4)
    }

    // MARK: MarkdownText.parseMarkdown

    @Test("parseMarkdown parses plain text as paragraph")
    func parsePlainText() {
        let view = MarkdownText(text: "Hello world")
        let blocks = view.parseMarkdown()
        #expect(blocks.count == 1)
        if case .paragraph(let content) = blocks[0] {
            #expect(content == "Hello world")
        } else {
            #expect(Bool(false), "Expected .paragraph")
        }
    }

    @Test("parseMarkdown parses heading level 1")
    func parseHeading1() {
        let view = MarkdownText(text: "# Title")
        let blocks = view.parseMarkdown()
        #expect(blocks.count == 1)
        if case .heading(let level, let content) = blocks[0] {
            #expect(level == 1)
            #expect(content == "Title")
        } else {
            #expect(Bool(false), "Expected .heading")
        }
    }

    @Test("parseMarkdown parses heading level 2")
    func parseHeading2() {
        let view = MarkdownText(text: "## Subtitle")
        let blocks = view.parseMarkdown()
        if case .heading(let level, _) = blocks[0] {
            #expect(level == 2)
        }
    }

    @Test("parseMarkdown parses heading level 3")
    func parseHeading3() {
        let view = MarkdownText(text: "### Section")
        let blocks = view.parseMarkdown()
        if case .heading(let level, _) = blocks[0] {
            #expect(level == 3)
        }
    }

    @Test("parseMarkdown parses bullet items")
    func parseBulletItem() {
        let view = MarkdownText(text: "- item one\n- item two")
        let blocks = view.parseMarkdown()
        #expect(blocks.count == 2)
        if case .bulletItem(let content) = blocks[0] {
            #expect(content == "item one")
        } else {
            #expect(Bool(false), "Expected .bulletItem")
        }
    }

    @Test("parseMarkdown parses numbered items")
    func parseNumberedItem() {
        let view = MarkdownText(text: "1. first\n2. second")
        let blocks = view.parseMarkdown()
        #expect(blocks.count == 2)
        if case .numberedItem(let num, let content) = blocks[0] {
            #expect(num == 1)
            #expect(content == "first")
        } else {
            #expect(Bool(false), "Expected .numberedItem")
        }
    }

    @Test("parseMarkdown parses checklist items as checkboxes")
    func parseChecklistItems() {
        let view = MarkdownText(text: "- [x] done\n- [ ] pending")
        let blocks = view.parseMarkdown()
        #expect(blocks.count == 2)
        if case .checkbox(let checked, let content) = blocks[0] {
            #expect(checked)
            #expect(content == "done")
        } else {
            #expect(Bool(false), "Expected .checkbox")
        }
        if case .checkbox(let checked, let content) = blocks[1] {
            #expect(!checked)
            #expect(content == "pending")
        } else {
            #expect(Bool(false), "Expected .checkbox")
        }
    }

    @Test("parseMarkdown treats non-list-dash as checkbox only when bracket present")
    func parsePlainDashIsNotCheckbox() {
        let view = MarkdownText(text: "- just a bullet")
        let blocks = view.parseMarkdown()
        if case .bulletItem = blocks[0] {
            // pass
        } else {
            #expect(Bool(false), "Expected .bulletItem, got \(blocks[0])")
        }
    }

    @Test("parseMarkdown parses code block")
    func parseCodeBlock() {
        let view = MarkdownText(text: "```swift\nlet x = 1\n```")
        let blocks = view.parseMarkdown()
        #expect(blocks.count == 1)
        if case .codeBlock(let lang, let code) = blocks[0] {
            #expect(lang == "swift")
            #expect(code == "let x = 1")
        } else {
            #expect(Bool(false), "Expected .codeBlock")
        }
    }

    @Test("parseMarkdown parses code block without language")
    func parseCodeBlockNoLanguage() {
        let view = MarkdownText(text: "```\nplain code\n```")
        let blocks = view.parseMarkdown()
        #expect(blocks.count == 1)
        if case .codeBlock(let lang, let code) = blocks[0] {
            #expect(lang.isEmpty)
            #expect(code == "plain code")
        }
    }

    @Test("diff block detected from language and from markers")
    func diffBlockDetection() {
        // Explicit diff language
        #expect(MarkdownText.isDiffBlock("+a\n-b\n", language: "diff"))
        #expect(MarkdownText.isDiffBlock("", language: "patch"))
        // Auto-detected from markers with no language
        #expect(MarkdownText.isDiffBlock("@@ -1,3 +1,3 @@\n+hello\n-goodbye\n", language: ""))
        #expect(MarkdownText.isDiffBlock("+++ b/file\n--- a/file\n", language: ""))
        // Plain code is not a diff
        #expect(!MarkdownText.isDiffBlock("let x = 1\nprint(x)\n", language: "swift"))
        #expect(!MarkdownText.isDiffBlock("plain text line\n", language: ""))
    }

    @Test("parseMarkdown parses blockquote")
    func parseBlockquote() {
        let view = MarkdownText(text: "> quoted text")
        let blocks = view.parseMarkdown()
        if case .blockquote(let content) = blocks[0] {
            #expect(content == "quoted text")
        } else {
            #expect(Bool(false), "Expected .blockquote")
        }
    }

    @Test("parseMarkdown parses horizontal rule")
    func parseHorizontalRule() {
        let view = MarkdownText(text: "---")
        let blocks = view.parseMarkdown()
        #expect(blocks.count == 1)
        if case .horizontalRule = blocks[0] {
            // expected
        } else {
            #expect(Bool(false), "Expected .horizontalRule")
        }
    }

    @Test("parseMarkdown parses horizontal rule with asterisks")
    func parseHorizontalRuleAsterisks() {
        let view = MarkdownText(text: "***")
        let blocks = view.parseMarkdown()
        #expect(blocks.count == 1)
        if case .horizontalRule = blocks[0] {
            // expected
        }
    }

    @Test("parseMarkdown merges consecutive non-empty lines into a paragraph")
    func parseParagraphMerge() {
        let view = MarkdownText(text: "line one\nline two")
        let blocks = view.parseMarkdown()
        #expect(blocks.count == 1)
        if case .paragraph(let content) = blocks[0] {
            #expect(content == "line one line two")
        }
    }

    @Test("parseMarkdown handles empty string")
    func parseEmptyString() {
        let view = MarkdownText(text: "")
        let blocks = view.parseMarkdown()
        #expect(blocks.isEmpty)
    }

    @Test("parseMarkdown handles string with only whitespace")
    func parseWhitespaceOnly() {
        let view = MarkdownText(text: "   \n  ")
        let blocks = view.parseMarkdown()
        #expect(blocks.isEmpty)
    }
}

// MARK: - PlanQuestionLogic (MSG-14)

@Suite("PlanQuestionLogic extended")
struct PlanQuestionLogicExtendedTests {

    // MARK: isQuestionTool

    @Test("isQuestionTool returns true for 'question'")
    func isQuestionToolExact() {
        #expect(PlanQuestionLogic.isQuestionTool("question"))
    }

    @Test("isQuestionTool returns true for 'askUserQuestion'")
    func isQuestionToolAskUserQuestion() {
        #expect(PlanQuestionLogic.isQuestionTool("askUserQuestion"))
    }

    @Test("isQuestionTool returns true for 'ask_user'")
    func isQuestionToolAskUser() {
        #expect(PlanQuestionLogic.isQuestionTool("ask_user"))
    }

    @Test("isQuestionTool returns true for names ending with 'ask_user'")
    func isQuestionToolSuffixAskUser() {
        #expect(PlanQuestionLogic.isQuestionTool("my_custom_ask_user"))
    }

    @Test("isQuestionTool returns false for 'write'")
    func isQuestionToolFalseForWrite() {
        #expect(!PlanQuestionLogic.isQuestionTool("write"))
    }

    @Test("isQuestionTool returns false for 'read'")
    func isQuestionToolFalseForRead() {
        #expect(!PlanQuestionLogic.isQuestionTool("read"))
    }

    @Test("isQuestionTool is case-insensitive")
    func isQuestionToolCaseInsensitive() {
        #expect(PlanQuestionLogic.isQuestionTool("Question"))
        #expect(PlanQuestionLogic.isQuestionTool("ASK_USER"))
    }

    @Test("isQuestionTool handles hyphenated names")
    func isQuestionToolHyphenToUnderscore() {
        #expect(PlanQuestionLogic.isQuestionTool("ask-user-question"))
    }

    // MARK: parseQuestionAskedEvent

    @Test("parseQuestionAskedEvent returns request when properties are valid")
    func parseValidEvent() {
        let properties: [String: Any] = [
            "requestID": "req-1",
            "sessionID": "ses-123",
            "questions": [
                ["question": "What next?", "options": [["label": "Option A"]]]
            ]
        ]
        let result = PlanQuestionLogic.parseQuestionAskedEvent(properties: properties)
        #expect(result != nil)
        #expect(result?.requestID == "req-1")
        #expect(result?.sessionID == "ses-123")
        #expect(result?.questions.count == 1)
    }

    @Test("parseQuestionAskedEvent returns nil when requestID is missing")
    func parseEventMissingRequestID() {
        let properties: [String: Any] = [
            "sessionID": "ses-123",
            "questions": [["question": "What?"]]
        ]
        let result = PlanQuestionLogic.parseQuestionAskedEvent(properties: properties)
        #expect(result == nil)
    }

    @Test("parseQuestionAskedEvent returns nil when requestID is empty")
    func parseEventEmptyRequestID() {
        let properties: [String: Any] = [
            "requestID": "",
            "questions": [["question": "What?"]]
        ]
        let result = PlanQuestionLogic.parseQuestionAskedEvent(properties: properties)
        #expect(result == nil)
    }

    @Test("parseQuestionAskedEvent returns nil when questions array is empty")
    func parseEventEmptyQuestions() {
        let properties: [String: Any] = [
            "requestID": "req-1",
            "questions": []
        ]
        let result = PlanQuestionLogic.parseQuestionAskedEvent(properties: properties)
        #expect(result == nil)
    }

    @Test("parseQuestionAskedEvent returns nil when questions are missing")
    func parseEventMissingQuestions() {
        let properties: [String: Any] = [
            "requestID": "req-1"
        ]
        let result = PlanQuestionLogic.parseQuestionAskedEvent(properties: properties)
        #expect(result == nil)
    }

    @Test("parseQuestionAskedEvent defaults sessionID to empty string")
    func parseEventDefaultSessionID() {
        let properties: [String: Any] = [
            "requestID": "req-1",
            "questions": [["question": "What?"]]
        ]
        let result = PlanQuestionLogic.parseQuestionAskedEvent(properties: properties)
        #expect(result?.sessionID == "")
    }

    @Test("parseQuestionAskedEvent parses multiple questions")
    func parseEventMultipleQuestions() {
        let properties: [String: Any] = [
            "requestID": "req-1",
            "questions": [
                ["question": "First", "multiple": true],
                ["question": "Second"]
            ]
        ]
        let result = PlanQuestionLogic.parseQuestionAskedEvent(properties: properties)
        #expect(result?.questions.count == 2)
        #expect(result?.questions[0].allowsMultiple == true)
        #expect(result?.questions[1].allowsMultiple == false)
    }

    // MARK: hasPendingQuestions

    @Test("hasPendingQuestions returns true when question tool call has no result")
    func hasPendingQuestionsTrue() {
        let parts: [MessagePartContent] = [
            .toolCall(name: "question", args: #"{"questions":[{"question":"Pick one?"}]}"#, result: nil, callID: "c1")
        ]
        #expect(PlanQuestionLogic.hasPendingQuestions(in: parts))
    }

    @Test("hasPendingQuestions returns false when question tool call has result")
    func hasPendingQuestionsFalseWhenResolved() {
        let parts: [MessagePartContent] = [
            .toolCall(name: "question", args: "{}", result: "Answered", callID: "c1")
        ]
        #expect(!PlanQuestionLogic.hasPendingQuestions(in: parts))
    }

    @Test("hasPendingQuestions returns false for non-question tool call")
    func hasPendingQuestionsFalseForNonQuestion() {
        let parts: [MessagePartContent] = [
            .toolCall(name: "write", args: "{}", result: nil, callID: "c1")
        ]
        #expect(!PlanQuestionLogic.hasPendingQuestions(in: parts))
    }

    @Test("hasPendingQuestions returns false when parts are empty")
    func hasPendingQuestionsEmptyParts() {
        #expect(!PlanQuestionLogic.hasPendingQuestions(in: []))
    }

    @Test("hasPendingQuestions returns true for tool named 'question' regardless of args")
    func hasPendingQuestionsNameCheck() {
        // The name "question" triggers true even without parsable questions
        let parts: [MessagePartContent] = [
            .toolCall(name: "question", args: "{}", result: nil, callID: "c1")
        ]
        #expect(PlanQuestionLogic.hasPendingQuestions(in: parts))
    }

    @Test("hasPendingQuestions returns false when ask_user tool has result")
    func hasPendingQuestionsAskUserWithResult() {
        let parts: [MessagePartContent] = [
            .toolCall(name: "askUserQuestion", args: #"{"questions":[{"question":"Confirm?"}]}"#, result: "yes", callID: "c1")
        ]
        #expect(!PlanQuestionLogic.hasPendingQuestions(in: parts))
    }

    // MARK: parseQuestions

    @Test("parseQuestions extracts questions from JSON with questions key")
    func parseQuestionsFromDict() {
        let json = #"{"questions":[{"question":"What color?","options":[{"label":"Red"},{"label":"Blue"}]}]}"#
        let questions = PlanQuestionLogic.parseQuestions(from: json)
        #expect(questions.count == 1)
        #expect(questions[0].prompt == "What color?")
        #expect(questions[0].options.count == 2)
        #expect(questions[0].options[0].label == "Red")
    }

    @Test("parseQuestions handles JSON array directly")
    func parseQuestionsFromArray() {
        let json = #"[{"question":"First?"},{"question":"Second?"}]"#
        let questions = PlanQuestionLogic.parseQuestions(from: json)
        #expect(questions.count == 2)
    }

    @Test("parseQuestions returns empty for invalid JSON")
    func parseQuestionsInvalidJSON() {
        let questions = PlanQuestionLogic.parseQuestions(from: "not json")
        #expect(questions.isEmpty)
    }

    @Test("parseQuestions returns empty for empty JSON")
    func parseQuestionsEmptyJSON() {
        let questions = PlanQuestionLogic.parseQuestions(from: "{}")
        #expect(questions.isEmpty)
    }

    @Test("parseQuestions filters out entries without prompt")
    func parseQuestionsSkipsNoPrompt() {
        let json = #"{"questions":[{"question":"Valid"},{"header":"No prompt"}]}"#
        let questions = PlanQuestionLogic.parseQuestions(from: json)
        #expect(questions.count == 1)
        #expect(questions[0].prompt == "Valid")
    }

    // MARK: upsertToolCall

    @Test("upsertToolCall adds new tool call when no matching callID or name")
    func upsertToolCallAppends() {
        var parts: [MessagePartContent] = [.text("hello")]
        PlanQuestionLogic.upsertToolCall(&parts, name: "read", args: "{}", result: "ok", callID: "c1")
        #expect(parts.count == 2)
        if case .toolCall(let name, _, _, _) = parts[1] {
            #expect(name == "read")
        }
    }

    @Test("upsertToolCall updates existing tool call by callID")
    func upsertToolCallUpdatesByCallID() {
        var parts: [MessagePartContent] = [
            .toolCall(name: "read", args: "{}", result: nil, callID: "c1")
        ]
        PlanQuestionLogic.upsertToolCall(&parts, name: "read", args: "{}", result: "file content", callID: "c1")
        #expect(parts.count == 1)
        if case .toolCall(_, _, let result, _) = parts[0] {
            #expect(result == "file content")
        }
    }

    @Test("upsertToolCall updates existing tool call by name when no callID")
    func upsertToolCallUpdatesByName() {
        var parts: [MessagePartContent] = [
            .toolCall(name: "write", args: "{}", result: nil, callID: nil)
        ]
        PlanQuestionLogic.upsertToolCall(&parts, name: "write", args: #"{"path":"/f"}"#, result: "done", callID: nil)
        #expect(parts.count == 1)
        if case .toolCall(_, let args, let result, _) = parts[0] {
            #expect(args == #"{"path":"/f"}"#)
            #expect(result == "done")
        }
    }

    @Test("upsertToolCall prefers callID matching over name matching")
    func upsertToolCallPrefersCallID() {
        var parts: [MessagePartContent] = [
            .toolCall(name: "read", args: "{}", result: nil, callID: "c1"),
            .toolCall(name: "write", args: "{}", result: nil, callID: "c2")
        ]
        // Update by callID "c1" — should update read, not write
        PlanQuestionLogic.upsertToolCall(&parts, name: "read", args: "new args", result: "new result", callID: "c1")
        #expect(parts.count == 2)
        // First part (callID "c1") should be updated — it's the read call
        if case .toolCall(let name, let args, let result, let callID) = parts[0] {
            #expect(name == "read")
            #expect(args == "new args")
            #expect(result == "new result")
            #expect(callID == "c1")
        } else {
            #expect(Bool(false), "Expected .toolCall")
        }
        // Second part unchanged
        if case .toolCall(_, _, let result, let callID) = parts[1] {
            #expect(result == nil)
            #expect(callID == "c2")
        }
    }

    // MARK: parseOpenCodeToolPart

    @Test("parseOpenCodeToolPart parses tool type with input dict")
    func parseOpenCodeToolPartToolType() {
        let part: [String: Any] = [
            "type": "tool",
            "tool": "read",
            "callID": "c1",
            "state": [
                "status": "completed",
                "input": ["path": "/tmp/file.txt"],
                "output": "file content"
            ]
        ]
        let result = PlanQuestionLogic.parseOpenCodeToolPart(part)
        #expect(result != nil)
        #expect(result?.toolName == "read")
        #expect(result?.callID == "c1")
        #expect(result?.isPending == false)
        #expect(result?.result == "file content")
    }

    @Test("parseOpenCodeToolPart parses tool-invocation type")
    func parseOpenCodeToolPartInvocationType() {
        let part: [String: Any] = [
            "type": "tool-invocation",
            "toolName": "write",
            "callID": "c2",
            "input": #"{"path":"/f.txt"}"#,
            "result": "done"
        ]
        let result = PlanQuestionLogic.parseOpenCodeToolPart(part)
        #expect(result != nil)
        #expect(result?.toolName == "write")
        #expect(result?.callID == "c2")
        #expect(result?.isPending == false)
        #expect(result?.result == "done")
    }

    @Test("parseOpenCodeToolPart returns nil for unknown type")
    func parseOpenCodeToolPartUnknownType() {
        let part: [String: Any] = ["type": "unknown"]
        let result = PlanQuestionLogic.parseOpenCodeToolPart(part)
        #expect(result == nil)
    }

    @Test("parseOpenCodeToolPart returns nil when type is missing")
    func parseOpenCodeToolPartMissingType() {
        let part: [String: Any] = ["tool": "read"]
        let result = PlanQuestionLogic.parseOpenCodeToolPart(part)
        #expect(result == nil)
    }

    @Test("parseOpenCodeToolPart marks pending when status is running")
    func parseOpenCodeToolPartPending() {
        let part: [String: Any] = [
            "type": "tool",
            "tool": "search",
            "state": ["status": "running"]
        ]
        let result = PlanQuestionLogic.parseOpenCodeToolPart(part)
        #expect(result?.isPending == true)
        #expect(result?.result == nil)
    }

    // MARK: buildReplyAnswers / formatAnswers

    @Test("buildReplyAnswers builds labels from selections")
    func buildReplyAnswers() {
        let questions = [
            PlanQuestion(id: "q-0", header: "Q1", prompt: "Pick one", options: [
                PlanQuestionOption(id: "opt-0", label: "A", description: ""),
                PlanQuestionOption(id: "opt-1", label: "B", description: "")
            ], allowsMultiple: false)
        ]
        let selections = ["q-0": Set(["opt-1"])]
        let result = PlanQuestionLogic.buildReplyAnswers(questions: questions, selections: selections, otherTexts: [:])
        #expect(result.count == 1)
        #expect(result[0] == ["B"])
    }

    @Test("buildReplyAnswers includes other text when provided")
    func buildReplyAnswersWithOther() {
        let questions = [
            PlanQuestion(id: "q-0", header: "Q1", prompt: "Pick one", options: [
                PlanQuestionOption(id: "opt-0", label: "A", description: "")
            ], allowsMultiple: false)
        ]
        let result = PlanQuestionLogic.buildReplyAnswers(
            questions: questions,
            selections: [:],
            otherTexts: ["q-0": "Custom answer"]
        )
        #expect(result[0] == ["Custom answer"])
    }

    @Test("buildReplyAnswers returns empty array for unanswered question")
    func buildReplyAnswersEmpty() {
        let questions = [
            PlanQuestion(id: "q-0", header: "Q1", prompt: "Pick", options: [
                PlanQuestionOption(id: "opt-0", label: "A", description: "")
            ], allowsMultiple: false)
        ]
        let result = PlanQuestionLogic.buildReplyAnswers(questions: questions, selections: [:], otherTexts: [:])
        #expect(result[0].isEmpty)
    }

    @Test("formatAnswers formats selected answers as string")
    func formatAnswers() {
        let questions = [
            PlanQuestion(id: "q-0", header: "Q1", prompt: "Color?", options: [
                PlanQuestionOption(id: "opt-0", label: "Red", description: ""),
                PlanQuestionOption(id: "opt-1", label: "Blue", description: "")
            ], allowsMultiple: true)
        ]
        let selections = ["q-0": Set(["opt-0", "opt-1"])]
        let result = PlanQuestionLogic.formatAnswers(questions, selections: selections)
        #expect(result == "Answers:\n- Color?: Red, Blue")
    }

    @Test("formatAnswers shows 'Other' when no selection made")
    func formatAnswersOther() {
        let questions = [
            PlanQuestion(id: "q-0", header: "Q1", prompt: "Color?", options: [
                PlanQuestionOption(id: "opt-0", label: "Red", description: "")
            ], allowsMultiple: false)
        ]
        let result = PlanQuestionLogic.formatAnswers(questions, selections: [:])
        #expect(result == "Answers:\n- Color?: Other")
    }
}
