import Testing
import Foundation
@testable import myCoder

@Suite("Settings Outside Dismiss")
struct SettingsOutsideDismissTests {

    @Test("Settings is presented as an overlay, not a modal sheet")
    func settingsIsOverlay() throws {
        let source = try sourceText("myCoder/Sources/Views/ContentView.swift")
        #expect(!source.contains(".sheet(isPresented: $appState.showSettings)"))
        #expect(source.contains("settingsOverlay"))
    }

    @Test("Clicking the dimmed backdrop closes settings")
    func backdropTapCloses() throws {
        let source = try sourceText("myCoder/Sources/Views/ContentView.swift")
        #expect(source.contains("onTapGesture { appState.showSettings = false }"))
    }

    @Test("Escape still closes settings after leaving sheet presentation")
    func escapeCloses() throws {
        let source = try sourceText("myCoder/Sources/Views/ContentView.swift")
        #expect(source.contains(".keyboardShortcut(.cancelAction)"))
    }

    private func sourceText(_ relativePath: String) throws -> String {
        try RepoRoot.sourceText(relativePath)
    }
}
