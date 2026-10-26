import Testing
@testable import myCoder

@Suite("Terminal font resolver")
struct TerminalFontResolverTests {

    @Test("Uses explicit override when set")
    func explicitOverride() {
        var settings = AppSettings()
        settings.terminalFont = "MesloLGS NF"
        settings.inheritTerminalProfile = true
        #expect(TerminalFontResolver.resolvedFontName(settings: settings) == "MesloLGS NF")
    }

    @Test("Falls back to monospaced system font when not inheriting and empty")
    func systemFallback() {
        var settings = AppSettings()
        settings.terminalFont = ""
        settings.inheritTerminalProfile = false
        let name = TerminalFontResolver.resolvedFontName(settings: settings)
        #expect(!name.isEmpty)
    }

    @Test("Display name marks inherited font")
    func inheritedDisplayName() {
        var settings = AppSettings()
        settings.terminalFont = ""
        settings.inheritTerminalProfile = true
        let label = TerminalFontResolver.displayLabel(settings: settings, language: .english)
        #expect(label.contains("inherited") || label.contains("Inherited"))
    }
}
