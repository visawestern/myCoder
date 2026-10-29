import Foundation
import Testing
@testable import myCoder

/// The Code Preview settings existed in `AppSettings` and in the Settings
/// screen but no renderer read them; these tests pin the mapping from the
/// stored values to the palette actually used by chat code blocks.
@Suite("Палитра кода из настроек")
struct CodeDisplaySettingsTests {

    @Test("Светлая и тёмная темы берутся из своих настроек")
    func resolvesThemeByInterfaceMode() {
        let settings = CodeDisplaySettings(
            lightThemeName: "One Light",
            darkThemeName: "Dracula"
        )
        #expect(settings.theme(isLightInterface: true) == .oneLight)
        #expect(settings.theme(isLightInterface: false) == .dracula)
    }

    @Test("Неизвестное имя темы откатывается к GitHub-палитре")
    func unknownThemeFallsBack() {
        let settings = CodeDisplaySettings(
            lightThemeName: "Not a theme",
            darkThemeName: "Also not a theme"
        )
        #expect(settings.theme(isLightInterface: true) == .githubLight)
        #expect(settings.theme(isLightInterface: false) == .githubDark)
    }

    @Test("AppSettings полностью переносится в настройки отображения кода")
    func mapsAppSettings() {
        var appSettings = AppSettings()
        appSettings.lightCodeTheme = "Solarized Light"
        appSettings.darkCodeTheme = "One Dark"
        appSettings.codeFontSize = 16
        appSettings.showLineNumbers = false
        appSettings.wrapLongLines = false

        let display = CodeDisplaySettings(settings: appSettings)
        #expect(display.lightThemeName == "Solarized Light")
        #expect(display.darkThemeName == "One Dark")
        #expect(display.fontSize == 16)
        #expect(display.showLineNumbers == false)
        #expect(display.wrapLongLines == false)
        #expect(display.theme(isLightInterface: false) == .oneDark)
    }

    @Test("Размер шрифта кода зажимается в допустимый диапазон")
    func clampsFontSize() {
        #expect(CodeDisplaySettings(fontSize: 2).clampedFontSize == 8)
        #expect(CodeDisplaySettings(fontSize: 12).clampedFontSize == 12)
        #expect(CodeDisplaySettings(fontSize: 99).clampedFontSize == 24)
    }

    @Test("Все темы из настроек имеют реальную палитру")
    func everyOfferedThemeHasPalette() {
        for theme in CodeTheme.allCases {
            let palette = theme.palette
            #expect(palette.background != palette.text)
            #expect(palette.keyword != palette.comment)
        }
    }
}
