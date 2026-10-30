import Foundation
import Testing
@testable import myCoder

@Suite("ChatScrollLogic — нижняя видимость и отступ")
struct ChatScrollLogicTests {

    @Test("bottomContentInset равен 20 pt (зазор под композером)")
    func bottomInsetIsTwenty() {
        #expect(ChatScrollLogic.bottomContentInset == 20)
    }

    @Test("Сентинел внутри вьюпорта — видим")
    func sentinelInsideViewportIsVisible() {
        let viewport = CGRect(x: 0, y: 0, width: 800, height: 600)
        let bottom = CGRect(x: 0, y: 590, width: 800, height: 10)
        #expect(ChatScrollLogic.bottomVisibility(bottomFrame: bottom, viewport: viewport) == true)
    }

    @Test("Сентинел под вьюпортом — не видим")
    func sentinelBelowViewportIsNotVisible() {
        let viewport = CGRect(x: 0, y: 0, width: 800, height: 600)
        let bottom = CGRect(x: 0, y: 700, width: 800, height: 10)
        #expect(ChatScrollLogic.bottomVisibility(bottomFrame: bottom, viewport: viewport) == false)
    }

    @Test("Сентинел глубоко выше вьюпорта — не видим")
    func sentinelAboveViewportIsNotVisible() {
        let viewport = CGRect(x: 0, y: 0, width: 800, height: 600)
        let bottom = CGRect(x: 0, y: -500, width: 800, height: 10)
        #expect(ChatScrollLogic.bottomVisibility(bottomFrame: bottom, viewport: viewport) == false)
    }

    @Test("Пустой вьюпорт или нулевая высота — nil (без скачков)")
    func unknownFramesYieldNil() {
        let viewport = CGRect.zero
        let bottom = CGRect(x: 0, y: 0, width: 800, height: 10)
        #expect(ChatScrollLogic.bottomVisibility(bottomFrame: bottom, viewport: viewport) == nil)
        #expect(ChatScrollLogic.bottomVisibility(bottomFrame: .zero, viewport: CGRect(x: 0, y: 0, width: 800, height: 600)) == nil)
    }

    @Test("Граница с допустимым допуском (1 pt) — видим")
    func toleranceEdgeIsVisible() {
        let viewport = CGRect(x: 0, y: 0, width: 800, height: 600)
        let bottom = CGRect(x: 0, y: 601, width: 800, height: 1)
        #expect(ChatScrollLogic.bottomVisibility(bottomFrame: bottom, viewport: viewport) == true)
    }
}
