import Testing
import Foundation
@testable import myCoder

@Suite("Selection Restore Logic")
struct SelectionRestoreLogicTests {

    @Test("Preferred provider is restored once it appears in options")
    func restoresPreferredWhenAvailable() {
        let resolved = SelectionRestoreLogic.resolvedProviderID(
            preferred: "mimo",
            current: "fallback",
            options: ["fallback", "mimo"]
        )
        #expect(resolved == "mimo")
    }

    @Test("No change when the preferred provider is already selected")
    func noChangeWhenAlreadySelected() {
        let resolved = SelectionRestoreLogic.resolvedProviderID(
            preferred: "mimo",
            current: "mimo",
            options: ["mimo"]
        )
        #expect(resolved == nil)
    }

    @Test("Preference is kept (not clobbered) while its provider is offline")
    func keepsPreferenceWhileUnavailable() {
        let resolved = SelectionRestoreLogic.resolvedProviderID(
            preferred: "mimo",
            current: "fallback",
            options: ["fallback"]
        )
        #expect(resolved == nil)
    }

    @Test("Empty preference never forces a change")
    func emptyPreferenceIgnored() {
        let resolved = SelectionRestoreLogic.resolvedProviderID(
            preferred: "",
            current: "any",
            options: ["any", "other"]
        )
        #expect(resolved == nil)
    }

    @Test("AppState separates user preference from fallback auto-selection")
    func appStateWiresPreference() throws {
        let source = try sourceText("myCoder/Sources/App/MyCoderApp.swift")
        #expect(source.contains("preferredProviderID"))
        #expect(source.contains("SelectionRestoreLogic.resolvedProviderID"))
        #expect(source.contains("persistPreference"))
    }

    private func sourceText(_ relativePath: String) throws -> String {
        try RepoRoot.sourceText(relativePath)
    }
}
