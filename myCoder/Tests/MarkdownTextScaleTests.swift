import Testing
import Foundation
@testable import myCoder

@Suite("Markdown Text Scale")
struct MarkdownTextScaleTests {

    @Test("Markdown text accepts custom base font size")
    func customFontSize() {
        let view = MarkdownText(text: "Hello", fontSize: 12)
        #expect(view.fontSize == 12)
    }

    @Test("Default markdown font size is 14")
    func defaultFontSize() {
        let view = MarkdownText(text: "Hello")
        #expect(view.fontSize == 14)
    }
}
