import Foundation
import Testing
@testable import myCoder

/// Safe Markdown → HTML used by the standalone chat book.
@Suite("Markdown book renderer")
struct MarkdownBookRendererTests {

    @Test func escapesRawHTMLBeforeRendering() {
        let html = MarkdownBookRenderer.render("<script>alert(1)</script>")
        #expect(!html.contains("<script>"))
        #expect(html.contains("&lt;script&gt;"))
    }

    @Test func rendersHeadingsParagraphsAndRules() {
        let html = MarkdownBookRenderer.render("# Title\n\nSome text\n\n---")
        #expect(html.contains("<h1>Title</h1>"))
        #expect(html.contains("<p>Some text</p>"))
        #expect(html.contains("<hr>"))
    }

    @Test func rendersFencedCodeVerbatimAndEscaped() {
        let html = MarkdownBookRenderer.render("```swift\nlet x = \"<a>\"\n```")
        #expect(html.contains("<pre><code class=\"language-swift\">"))
        #expect(html.contains("let x = &quot;&lt;a&gt;&quot;"))
    }

    @Test func rendersListsBlockquotesAndInlineFormatting() {
        let html = MarkdownBookRenderer.render("""
        - one
        - **two**
        1. first
        > quoted
        `code` and [link](https://example.com)
        """)
        #expect(html.contains("<ul>"))
        #expect(html.contains("<li>one</li>"))
        #expect(html.contains("<strong>two</strong>"))
        #expect(html.contains("<ol>"))
        #expect(html.contains("<blockquote>quoted</blockquote>"))
        #expect(html.contains("<code>code</code>"))
        #expect(html.contains("href=\"https://example.com\""))
    }

    @Test func refusesJavaScriptLinks() {
        let html = MarkdownBookRenderer.render("[click](javascript:alert(1))")
        #expect(!html.contains("href=\"javascript:"))
        #expect(html.contains("[click](javascript:alert(1))"))
    }

    @Test func escapeCoversEveryHTMLSignificantCharacter() {
        #expect(MarkdownBookRenderer.escape("&<>\"'") == "&amp;&lt;&gt;&quot;&#39;")
    }
}

/// The standalone HTML book: one chapter per sent prompt, fixed TOC,
/// pagination, themes and tool results.
@Suite("Chat HTML book")
struct ChatHTMLBookTests {

    private func chat() -> [Message] {
        [
            Message(role: .user, content: "Первый вопрос"),
            Message(role: .assistant, content: "Первый ответ", parts: [.text("Первый ответ")]),
            Message(
                role: .assistant,
                content: "",
                parts: [.toolCall(
                    name: "read_file",
                    args: #"{"path":"A.swift"}"#,
                    result: "let a = 1",
                    callID: "c1"
                )]
            ),
            Message(role: .user, content: "Второй вопрос"),
            Message(role: .assistant, content: "Второй ответ", parts: [.text("Второй ответ")])
        ]
    }

    @Test func buildsOneChapterPerUserPromptAndAttachesAssistantContent() {
        let chapters = ChatHTMLBook.chapters(from: ChatExportLogic.entries(from: chat()))
        #expect(chapters.count == 2)
        #expect(chapters[0].title == "Первый вопрос")
        #expect(chapters[0].entries.count == 3)
        #expect(chapters[1].title == "Второй вопрос")
        #expect(chapters[1].entries.count == 2)
    }

    @Test func entriesBeforeTheFirstPromptBecomeTheOpeningChapter() {
        let messages = [Message(role: .assistant, content: "intro", parts: [.text("intro")])]
        let chapters = ChatHTMLBook.chapters(from: ChatExportLogic.entries(from: messages))
        #expect(chapters.count == 1)
        #expect(chapters[0].title == "Chat")
    }

    @Test func rendersCompleteStandaloneBook() {
        let html = ChatHTMLBook.render(
            messages: chat(), title: "Сборка",
            exportedAt: Date(timeIntervalSince1970: 0)
        )
        #expect(html.hasPrefix("<!DOCTYPE html>"))
        #expect(html.contains("<title>Сборка</title>"))
        #expect(!html.contains("{{TITLE}}"))
        #expect(!html.contains("{{TOC}}"))
        #expect(!html.contains("{{PAGES}}"))
        #expect(!html.contains("{{CHAPTER_COUNT}}"))
        #expect(!html.contains("{{EXPORTED_AT}}"))
        #expect(html.contains("2 chapters"))
        #expect(html.contains("id=\"page-1\""))
        #expect(html.contains("id=\"page-2\""))
        #expect(html.contains("data-page=\"1\""))
        #expect(html.contains("data-theme=\"dark\""))
        #expect(html.contains("toggleTheme()"))
        #expect(html.contains("id=\"prev\""))
        #expect(html.contains("id=\"next\""))
        #expect(html.contains("<details class=\"tool\">"))
        #expect(html.contains("let a = 1"))
    }

    @Test func everyExportedBookUsesTheOneReusableTemplate() {
        let stamp = Date(timeIntervalSince1970: 0)
        let first = ChatHTMLBook.render(messages: chat(), title: "BookOne", exportedAt: stamp)
        let second = ChatHTMLBook.render(messages: chat(), title: "BookTwo", exportedAt: stamp)
        #expect(first.contains("myCoder"))
        #expect(second.contains("myCoder"))
        // Only the title differs between two books from the same chat.
        let normalizedFirst = first.replacingOccurrences(of: "BookOne", with: "BookTwo")
        #expect(normalizedFirst == second)
    }

    @Test func chapterTitlesAreTrimmedAndTruncated() {
        let long = String(repeating: "слово ", count: 40)
        let messages = [Message(role: .user, content: "##  \(long)")]
        let chapters = ChatHTMLBook.chapters(from: ChatExportLogic.entries(from: messages))
        #expect(chapters.count == 1)
        #expect(chapters[0].title.count <= 64)
        #expect(chapters[0].title.hasPrefix("слово"))
        #expect(!chapters[0].title.hasPrefix("#"))
    }

    @Test func userTextIsEscapedInsideTheBook() {
        let messages = [Message(role: .user, content: "<img src=x onerror=alert(1)>")]
        let html = ChatHTMLBook.render(messages: messages, title: "T")
        #expect(!html.contains("<img src=x"))
        #expect(html.contains("&lt;img src=x"))
    }
}
