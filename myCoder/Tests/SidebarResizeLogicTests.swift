import Testing
@testable import myCoder

@Suite("Sidebar resize logic (plan Раздел 11 Блок 1)")
struct SidebarResizeLogicTests {

    @Test func clampRespectsBounds() {
        #expect(SidebarResizeLogic.clamp(150) == 200)
        #expect(SidebarResizeLogic.clamp(500) == 420)
        #expect(SidebarResizeLogic.clamp(300) == 300)
    }

    @Test func applyDragAddsTranslationThenClamps() {
        #expect(SidebarResizeLogic.applyDrag(current: 260, translation: 40) == 300)
        #expect(SidebarResizeLogic.applyDrag(current: 410, translation: 100) == 420)
        #expect(SidebarResizeLogic.applyDrag(current: 210, translation: -100) == 200)
    }

    @Test func applyDragNegativeTranslationShrinks() {
        #expect(SidebarResizeLogic.applyDrag(current: 260, translation: -60) == 200)
    }

    @Test func dragSamplesUseTheSameGestureBaseline() {
        let baseline = 260.0
        let samples = [10.0, 20.0, 30.0].map {
            SidebarResizeLogic.applyDrag(current: baseline, translation: $0)
        }
        #expect(samples == [270.0, 280.0, 290.0])
    }

    @Test func resetReturnsDefault() {
        #expect(SidebarResizeLogic.reset() == 260)
        #expect(SidebarResizeLogic.defaultWidth == 260)
    }

    @Test func customBoundsAreRespected() {
        #expect(SidebarResizeLogic.clamp(50, min: 100, max: 800) == 100)
        #expect(SidebarResizeLogic.clamp(1000, min: 100, max: 800) == 800)
    }
}
