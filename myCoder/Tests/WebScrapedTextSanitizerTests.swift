import Foundation
import Testing
@testable import myCoder

/// Live evidence from the last chat (session C9AB8206, 2026-09-12): every
/// fenced block in the saved answer carried vendor code chrome as text —
/// the "tool" language chip and the localized copy button ("Копировать").
/// The sanitizer must strip those standalone chip lines while preserving
/// real content, fences, and prose that merely contains the words.
@Suite("WEB-CHAT-12: scraped vendor chrome sanitizer")
struct WebScrapedTextSanitizerTests {

    @Test("chrome lines around a tool block are stripped")
    func stripsToolAndCopyChips() {
        let scraped = """
        Вот вызов:
        ```tool
        tool
        Копировать
        {"name": "list_dir", "args": {"path": "."}}
        ```
        """
        let clean = WebScrapedTextSanitizer.sanitizeAnswer(scraped)
        #expect(!clean.contains("Копировать"))
        #expect(!clean.contains("\ntool\n"))
        #expect(clean.contains("```tool"))
        #expect(clean.contains(#"{"name": "list_dir", "args": {"path": "."}}"#))
    }

    @Test("prose containing the word Copy is untouched")
    func preservesProseWithChipWords() {
        let prose = "To copy the file use cp. Copy the output below."
        #expect(WebScrapedTextSanitizer.sanitizeAnswer(prose) == prose)
    }

    @Test("localized copy labels all match standalone")
    func localizedLabels() {
        for label in ["копировать", "Copy", "复制", "コピー", "Kopieren", "Copiar"] {
            let text = "line one\n\(label)\nline two"
            let clean = WebScrapedTextSanitizer.sanitizeAnswer(text)
            #expect(clean == "line one\nline two", "failed for \(label)")
        }
    }

    @Test("fence delimiters survive, chrome-only fence collapses")
    func fenceHandling() {
        let withCode = """
        ```swift
        let a = 1
        ```
        """
        #expect(WebScrapedTextSanitizer.sanitizeAnswer(withCode) == withCode)

        let chromeOnly = "```\ntool\nКопировать\n```"
        #expect(WebScrapedTextSanitizer.sanitizeAnswer(chromeOnly).isEmpty)
    }

    @Test("streaming sanitize is idempotent")
    func idempotent() {
        let scraped = "text\nКопировать\n```tool\n{\"name\": \"grep\", \"args\": {}}\n```"
        let once = WebScrapedTextSanitizer.sanitizeStreaming(scraped)
        let twice = WebScrapedTextSanitizer.sanitizeStreaming(once)
        #expect(once == twice)
        #expect(once.contains("grep"))
    }

    @Test("longer chip-like line is treated as prose")
    func longChipLikeLineKept() {
        let line = "Copy the config into the new folder before running the build step"
        #expect(WebScrapedTextSanitizer.sanitizeAnswer(line) == line)
    }

    @Test("blank-line runs do not duplicate after stripping")
    func blankRunCollapse() {
        let scraped = "para one\n\nКопировать\n\n\npara two"
        let clean = WebScrapedTextSanitizer.sanitizeAnswer(scraped)
        #expect(clean == "para one\n\npara two")
    }
}
