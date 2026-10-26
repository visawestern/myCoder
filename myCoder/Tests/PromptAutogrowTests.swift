import Testing
import Foundation
import AppKit
@testable import myCoder

@Suite("Prompt Autogrow")
struct PromptAutogrowTests {

    @Test("Clamped height grows with content up to max")
    func clampedHeightGrows() {
        let oneLine = ZeroInsetTextField.clampedHeight(usedHeight: 18, pointSize: 14, minHeight: 36, maxHeight: 90)
        let threeLines = ZeroInsetTextField.clampedHeight(usedHeight: 54, pointSize: 14, minHeight: 36, maxHeight: 90)
        let tenLines = ZeroInsetTextField.clampedHeight(usedHeight: 180, pointSize: 14, minHeight: 36, maxHeight: 90)

        #expect(oneLine == 36)
        #expect(threeLines > oneLine)
        #expect(threeLines <= 90)
        #expect(tenLines == 90)
    }

    @Test("Clamped height never falls below min height")
    func clampedHeightRespectsMin() {
        let height = ZeroInsetTextField.clampedHeight(usedHeight: 0, pointSize: 14, minHeight: 36, maxHeight: 90)
        #expect(height == 36)
    }

    @Test("Compact prompt field uses a growing multiline editor, not a fixed single-line field")
    func compactFieldIsMultiline() throws {
        let source = try sourceText("myCoder/Sources/Views/Components/InputControls.swift")
        // The compact prompt must always be a multiline (autogrow) editor;
        // a single-line NSTextField cannot grow and truncates input.
        #expect(source.contains("multiline: true"))
        #expect(!source.contains("multiline: !compactSingleLine"))
    }

    @Test("Compact prompt max height allows growth beyond one line")
    func compactMaxHeightAllowsGrowth() throws {
        let source = try sourceText("myCoder/Sources/Views/Components/InputControls.swift")
        #expect(!source.contains("compactSingleLine ? InputLayout.compactTextHeight : InputLayout.textMaxHeight"))
    }

    private func sourceText(_ relativePath: String) throws -> String {
        try RepoRoot.sourceText(relativePath)
    }
}
