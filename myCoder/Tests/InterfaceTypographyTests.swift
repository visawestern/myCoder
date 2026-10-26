import Testing
import Foundation
@testable import myCoder

@Suite("Interface Typography")
struct InterfaceTypographyTests {

    @Test("Zoom fontScale values")
    func zoomFontScale() {
        #expect(AppSettings.Zoom.smaller.fontScale == 0.85)
        #expect(AppSettings.Zoom.default.fontScale == 1.0)
        #expect(AppSettings.Zoom.larger.fontScale == 1.15)
    }

    @Test("InterfaceTypography scales base sizes")
    func scaledSizes() {
        #expect(InterfaceTypography.scaled(13, scale: 1.15) == 15)
        #expect(InterfaceTypography.scaled(24, scale: 0.85) == 20)
        #expect(InterfaceTypography.scaled(12, scale: 1.0) == 12)
    }

    @Test("InputLayout metrics scale with zoom")
    func scaledInputLayout() {
        #expect(InputLayout.textMinHeight(scale: 1.15) == 28)
        #expect(InputLayout.toolbarHorizontalPadding(scale: 0.85) == 10)
        #expect(InputLayout.textMaxHeight(scale: 1.0) == 72)
    }

    @Test("ContentView does not use root scaleEffect for zoom")
    func contentViewSourceHasNoRootScaleEffect() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Views/ContentView.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        #expect(!source.contains(".scaleEffect(appState.settings.zoom"))
    }
}
