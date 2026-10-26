import Testing
@testable import myCoder

@Suite("Model Settings Layout")
struct ModelSettingsLayoutLogicTests {

    @Test("Uses compact layout inside a narrow settings sheet")
    func compactLayout() {
        #expect(ModelSettingsLayoutLogic.mode(availableWidth: 520) == .compact)
    }

    @Test("Keeps three columns when enough width is available")
    func wideLayout() {
        #expect(ModelSettingsLayoutLogic.mode(availableWidth: 900) == .wide)
    }

    @Test("Treats the exact three-column minimum as wide")
    func thresholdLayout() {
        #expect(
            ModelSettingsLayoutLogic.mode(
                availableWidth: ModelSettingsLayoutLogic.wideMinimumWidth
            ) == .wide
        )
    }
}
