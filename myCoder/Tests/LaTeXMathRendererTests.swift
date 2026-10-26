import Foundation
import Testing
@testable import myCoder

struct LaTeXMathRendererTests {

    @Test("Superscripts become Unicode raised digits")
    func superscripts() {
        #expect(LaTeXMathRenderer.render("x^{2} + x^3 = y") == "x² + x³ = y")
        #expect(LaTeXMathRenderer.render("E = mc^{2}") == "E = mc²")
        #expect(LaTeXMathRenderer.render("a^{10}") == "a¹⁰")
    }

    @Test("Subscripts become Unicode lowered digits")
    func subscripts() {
        #expect(LaTeXMathRenderer.render("a_{1} + a_2") == "a₁ + a₂")
        #expect(LaTeXMathRenderer.render("x_{n})") == "xₙ)")
    }

    @Test("Fractions become slash forms")
    func fractions() {
        #expect(LaTeXMathRenderer.render("\\frac{1}{2}") == "1/2")
        #expect(LaTeXMathRenderer.render("\\frac{a+b}{c}") == "a+b/c")
    }

    @Test("Roots become radical signs")
    func roots() {
        #expect(LaTeXMathRenderer.render("\\sqrt{x}") == "√(x)")
        #expect(LaTeXMathRenderer.render("\\sqrt{b^{2}-4ac}") == "√(b²-4ac)")
    }

    @Test("Greek and operator commands map to Unicode")
    func symbols() {
        #expect(LaTeXMathRenderer.render("\\alpha") == "α")
        #expect(LaTeXMathRenderer.render("\\sum_{i=1}^{n}") == "∑(i=1)ⁿ")
        #expect(LaTeXMathRenderer.render("\\infty") == "∞")
        #expect(LaTeXMathRenderer.render("\\leftarrow \\Rightarrow") == "← ⇒")
        // \left must vanish before \le maps to ≤.
        #expect(LaTeXMathRenderer.render("\\left( a \\right)") == "( a )")
    }

    @Test("Dollar heuristics reject pricing sentences")
    func dollarHeuristic() {
        #expect(!LaTeXMathRenderer.looksLikeMath("5 and 10 total"))
        #expect(LaTeXMathRenderer.looksLikeMath("\\alpha^2"))
    }

    @Test("\\(…\\) delimiters are extracted")
    func delimitedBodies() {
        #expect(LaTeXMathRenderer.delimitedBody("\\(E = mc^2\\)") == "E = mc^2")
        #expect(LaTeXMathRenderer.delimitedBody("plain") == nil)
    }

    @Test("Matrix environments keep readable contents")
    func matrices() {
        let rendered = LaTeXMathRenderer.render("\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}")
        #expect(rendered.contains("⎡"))
        #expect(rendered.contains("⎤"))
        #expect(rendered.contains("c"))
    }

    @Test("Parser recognizes $$ display math blocks")
    func displayMathBlocks() {
        let blocks = MarkdownDocumentParser.parse("Intro text\n\n$$\\frac{a}{b}$$\n\nMore text")
        #expect(blocks.count == 3)
        #expect(blocks[1] == .math("\\frac{a}{b}"))
    }

    @Test("Parser recognizes multiline $$ blocks")
    func multilineMath() {
        let markdown = "Before\n$$\na + b\n\\frac{c}{d}\n$$\nAfter"
        let blocks = MarkdownDocumentParser.parse(markdown)
        guard case let .math(latex) = blocks[1] else {
            Issue.record("expected math block, got \(blocks)")
            return
        }
        #expect(latex.contains("a + b"))
    }

    @Test("Parser recognizes \\[ … \\] display math")
    func bracketMath() {
        let blocks = MarkdownDocumentParser.parse("Text\n\\[ x^2 \\]\nTail")
        #expect(blocks[1] == .math("x^2"))
    }

    @Test("Inline math tokens are parsed from the three delimiter forms")
    func inlineMathParsing() {
        let parens = MarkdownInlineParser.parse("Value \\(x^2\\) stays inline")
        #expect(parens.contains(.mathInline("x²")))

        let brackets = MarkdownInlineParser.parse("Formula \\[a+b\\] inline")
        #expect(brackets.contains(.mathInline("a+b")))

        let dollars = MarkdownInlineParser.parse("Sum $\\alpha^2$ inside text")
        #expect(dollars.contains(.mathInline("α²")))
    }

    @Test("Dollar prices without math markers stay literal text")
    func dollarPricesStayText() {
        let parts = MarkdownInlineParser.parse("costs $5 and $10 total")
        #expect(parts == [.text("costs $5 and $10 total")])
    }
}
