import Testing
import Foundation
import SwiftUI
@testable import myCoder

@Suite("Settings Light Theme Controls")
struct SettingsLightThemeTests {

    @Test("Theme control surfaces stay visible on light and dark themes")
    func controlContrast() {
        Color.mimo.setTheme(.lightGlass)
        #expect(Color.mimo.controlBackground != Color.mimo.background)
        #expect(Color.mimo.surface != Color.mimo.backgroundAlt)

        Color.mimo.setTheme(.dark)
        #expect(Color.mimo.controlBackground != Color.mimo.background)
    }

    @Test("Light theme input fields use bright surfaces, not dark fill")
    func lightInputSurfacesAreBright() {
        Color.mimo.setTheme(.lightGlass)
        let input = ThemeColorLuminance.average(for: .input, theme: .lightGlass)
        let background = ThemeColorLuminance.average(for: .background, theme: .lightGlass)
        #expect(input > 0.88)
        #expect(input >= background - 0.05)

        Color.mimo.setTheme(.dark)
        let darkInput = ThemeColorLuminance.average(for: .input, theme: .dark)
        #expect(darkInput < 0.15)
    }

    @Test("App theme selects matching system color scheme")
    func preferredColorScheme() {
        #expect(AppTheme.lightGlass.preferredColorScheme == .light)
        #expect(AppTheme.dark.preferredColorScheme == .dark)
    }
}
