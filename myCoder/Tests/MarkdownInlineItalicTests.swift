import Testing
@testable import myCoder

@Suite("Markdown Inline Italic")
struct MarkdownInlineItalicTests {

    private func parse(_ s: String) -> [MarkdownInline.InlinePart] {
        MarkdownInline(text: s).parseInline(s)
    }

    @Test("Single-asterisk italic is parsed")
    func asteriskItalic() {
        let parts = parse("plain *emphasized* tail")
        #expect(parts.count == 3)
        guard case .text(let head) = parts[0], case .italic(let it) = parts[1], case .text(let tail) = parts[2] else {
            Issue.record("Unexpected parts: \(parts)")
            return
        }
        #expect(head == "plain ")
        #expect(it == "emphasized")
        #expect(tail == " tail")
    }

    @Test("Underscore italic is parsed")
    func underscoreItalic() {
        let parts = parse("_word_")
        guard case .italic(let it)? = parts.first else {
            Issue.record("Expected italic, got \(parts)")
            return
        }
        #expect(it == "word")
    }

    @Test("Bold is not consumed by italic")
    func boldStillBold() {
        let parts = parse("**strong** and *soft*")
        guard case .bold(let b) = parts[0], case .italic(let it) = parts[2] else {
            Issue.record("Unexpected parts: \(parts)")
            return
        }
        #expect(b == "strong")
        #expect(it == "soft")
    }

    @Test("Inline parts are emitted in source order")
    func sourceOrderPreserved() {
        let parts = parse("`code` then **bold**")
        guard case .code(let c) = parts[0], case .text = parts[1], case .bold(let b) = parts[2] else {
            Issue.record("Unexpected parts: \(parts)")
            return
        }
        #expect(c == "code")
        #expect(b == "bold")
    }

    @Test("Plain text without markers stays intact")
    func plainTextUntouched() {
        let parts = parse("no markers at all")
        #expect(parts.count == 1)
        guard case .text(let t)? = parts.first else {
            Issue.record("Expected text, got \(parts)")
            return
        }
        #expect(t == "no markers at all")
    }

    @Test("Markdown link is parsed with title and url")
    func markdownLink() {
        let parts = parse("see [docs](https://example.com/page)")
        guard case .text(let head) = parts[0], case .link(let title, let url) = parts[1] else {
            Issue.record("Unexpected parts: \(parts)")
            return
        }
        #expect(head == "see ")
        #expect(title == "docs")
        #expect(url == "https://example.com/page")
    }

    @Test("Bare URL inside text becomes a link")
    func bareUrlBecomesLink() {
        let parts = parse("visit https://example.com now")
        #expect(parts.contains { if case .link = $0 { return true }; return false })
    }
}
