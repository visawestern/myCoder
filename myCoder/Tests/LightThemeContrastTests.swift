import Testing
import Foundation
import SwiftUI
@testable import myCoder

@Suite("Light Theme Contrast")
struct LightThemeContrastTests {

    @Test("Light theme surfaces differ from background")
    func surfaceSeparation() {
        Color.mimo.setTheme(.lightGlass)
        let surface = ThemeColorLuminance.average(for: .surface, theme: .lightGlass)
        let background = ThemeColorLuminance.average(for: .background, theme: .lightGlass)
        #expect(abs(surface - background) > 0.01)
    }

    @Test("Light theme body text meets contrast on background")
    func textPrimaryContrast() {
        Color.mimo.setTheme(.lightGlass)
        let ratio = ThemeColorLuminance.contrastRatio(
            foreground: .textPrimary,
            background: .background,
            theme: .lightGlass
        )
        #expect(ratio >= 4.5)
    }

    @Test("Light theme muted text on surface meets large-text threshold")
    func mutedOnSurface() {
        Color.mimo.setTheme(.lightGlass)
        let ratio = ThemeColorLuminance.contrastRatio(
            foreground: .textMuted,
            background: .surface,
            theme: .lightGlass
        )
        #expect(ratio >= 3.0)
    }

    @Test("Light theme border is darker than background")
    func borderVisible() {
        Color.mimo.setTheme(.lightGlass)
        let border = ThemeColorLuminance.average(for: .border, theme: .lightGlass)
        let background = ThemeColorLuminance.average(for: .background, theme: .lightGlass)
        #expect(border < background)
    }

    @Test("Light theme code background differs from page background")
    func codeBgSeparation() {
        Color.mimo.setTheme(.lightGlass)
        let code = ThemeColorLuminance.average(for: .codeBg, theme: .lightGlass)
        let background = ThemeColorLuminance.average(for: .background, theme: .lightGlass)
        #expect(abs(code - background) > 0.02)
    }

    @Test("Dark theme retains control contrast")
    func darkNoRegression() {
        Color.mimo.setTheme(.dark)
        #expect(Color.mimo.controlBackground != Color.mimo.background)
        let ratio = ThemeColorLuminance.contrastRatio(
            foreground: .textPrimary,
            background: .background,
            theme: .dark
        )
        #expect(ratio >= 4.5)
        Color.mimo.setTheme(.lightGlass)
    }
}
