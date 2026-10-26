import Testing
@testable import myCoder

@Suite("Input Card Capsule Layout")
struct InputCardLayoutLogicTests {

    @Test("Header and footer start overlapped at center")
    func collapsedOffsets() {
        #expect(InputCardLayoutLogic.headerExpansionOffset(progress: 0) == InputCardLayoutLogic.headerExpansionTravel)
        #expect(InputCardLayoutLogic.footerExpansionOffset(progress: 0) == -InputCardLayoutLogic.footerExpansionTravel)
        #expect(InputCardLayoutLogic.sectionOpacity(progress: 0) == 0)
    }

    @Test("Header and footer settle at rest when expanded")
    func expandedOffsets() {
        #expect(InputCardLayoutLogic.headerExpansionOffset(progress: 1) == 0)
        #expect(InputCardLayoutLogic.footerExpansionOffset(progress: 1) == 0)
        #expect(InputCardLayoutLogic.sectionOpacity(progress: 1) == 1)
    }

    @Test("Single horizontal padding constant for capsule content")
    func unifiedHorizontalPadding() {
        #expect(InputCardLayoutLogic.contentHorizontalPadding == 14)
        #expect(InputCardLayoutLogic.contentHorizontalPadding == InputLayout.cardContentPadding)
    }
}
