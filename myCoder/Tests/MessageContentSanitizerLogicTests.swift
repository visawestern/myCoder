import Testing
@testable import myCoder

@Suite("Message content sanitizer")
struct MessageContentSanitizerLogicTests {

    @Test("Strips system-reminder blocks from displayed text")
    func stripsSystemReminder() {
        let raw = """
        составь план улучшения

        <system-reminder>
        Plan mode is active. Do not execute yet.
        </system-reminder>
        """
        let cleaned = MessageContentSanitizerLogic.sanitizedForDisplay(raw)
        #expect(cleaned.contains("составь план улучшения"))
        #expect(cleaned.contains("system-reminder") == false)
        #expect(cleaned.contains("Plan mode is active") == false)
    }

    @Test("Returns nil for empty text after sanitization")
    func emptyAfterSanitization() {
        #expect(
            MessageContentSanitizerLogic.sanitizedTextPart(
                "<system-reminder>only reminder</system-reminder>"
            ) == nil
        )
    }

    @Test("Falls back to formatted content when parts contain only service text")
    func formattedFallbackAfterEmptyParts() {
        let texts = MessageContentSanitizerLogic.displayTexts(
            partTexts: ["<system-reminder>only reminder</system-reminder>"],
            fallback: "✨ **Готово**"
        )

        #expect(texts == ["✨ **Готово**"])
    }

    @Test("Does not duplicate fallback when a visible text part exists")
    func visiblePartWinsOverFallback() {
        let texts = MessageContentSanitizerLogic.displayTexts(
            partTexts: ["✅ **Собрано**"],
            fallback: "duplicate"
        )

        #expect(texts == ["✅ **Собрано**"])
    }
}

@Suite("Think tag handling")
struct ThinkTagLogicTests {

    @Test("Closed think block moves to thinking, answer stays clean")
    func closedBlockExtracted() {
        let raw = "Let me summarize.\n<think>user wants a table</think>\nDone."
        let result = ThinkTagLogic.extract(from: raw)
        #expect(!result.cleaned.contains("user wants a table"))
        #expect(!result.cleaned.contains("<think>"))
        #expect(result.cleaned.contains("Let me summarize."))
        #expect(result.cleaned.contains("Done."))
        #expect(result.thinking == ["user wants a table"])
    }

    @Test("Stray closing tag is deleted without eating text")
    func strayClosingTagDeleted() {
        // Real-world case: `...checked.</think>Проверка...`
        let result = ThinkTagLogic.extract(from: "all tools checked.</think>Проверка завершена.")
        #expect(!result.cleaned.contains("think>"))
        #expect(result.cleaned.contains("all tools checked."))
        #expect(result.cleaned.contains("Проверка завершена."))
        #expect(result.thinking.isEmpty)
    }

    @Test("Tags match case-insensitively")
    func caseInsensitive() {
        let result = ThinkTagLogic.extract(from: "<THINK>hmm</THINK>Answer")
        #expect(result.cleaned == "Answer")
        #expect(result.thinking == ["hmm"])
    }

    @Test("Unclosed opener stays visible (fail-visible for streaming)")
    func unclosedOpenerKeepsText() {
        let result = ThinkTagLogic.extract(from: "Answer started<think>still thinking...")
        #expect(result.cleaned.contains("still thinking..."))
        #expect(!result.cleaned.contains("<think>"))
    }

    @Test("Think tags inside fenced code are preserved")
    func codeFencePreserved() {
        let raw = "```xml\n<root><think>not a tag</think></root>\n```\nReal answer"
        let result = ThinkTagLogic.extract(from: raw)
        #expect(result.cleaned.contains("<think>not a tag</think>"))
        #expect(result.cleaned.contains("Real answer"))
        #expect(result.thinking.isEmpty)
    }

    @Test("inlineThinking joins blocks for the spoiler")
    func inlineThinkingJoined() {
        #expect(ThinkTagLogic.inlineThinking(in: "a<think>one</think>b<think>two</think>c") == "one\n\ntwo")
        #expect(ThinkTagLogic.inlineThinking(in: "plain answer") == "")
    }

    @Test("Sanitizer strips think blocks from display text")
    func sanitizerStripsThink() {
        let cleaned = MessageContentSanitizerLogic.sanitizedForDisplay("<think>meta</think>Visible")
        #expect(cleaned == "Visible")
    }
}
@Suite("OpenCode tool status")
struct OpenCodeToolStatusLogicTests {

    @Test("Completed status with output is not pending")
    func completedWithOutput() {
        #expect(
            OpenCodeToolStatusLogic.isPending(status: "completed", output: "file contents")
            == false
        )
    }

    @Test("Running status stays pending without output")
    func runningPending() {
        #expect(OpenCodeToolStatusLogic.isPending(status: "running", output: nil))
    }

    @Test("Empty status with output is completed")
    func emptyStatusWithOutput() {
        #expect(OpenCodeToolStatusLogic.isPending(status: nil, output: "done") == false)
    }

    @Test("Extracts structured output as JSON")
    func extractsStructuredOutput() {
        let output = OpenCodeToolStatusLogic.extractOutput(from: [
            "output": ["content": "hello"]
        ])
        #expect(output?.contains("hello") == true)
    }
}
