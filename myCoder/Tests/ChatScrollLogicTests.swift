import Foundation
import Testing
@testable import myCoder

@MainActor
@Suite("ChatScrollLogic — нижняя видимость и отступ")
struct ChatScrollLogicTests {

    @Test("Во время ответа есть место для центрирования, после него оно убирается")
    func streamingTailExistsOnlyWhileFollowing() {
        #expect(ChatScrollLogic.followTailHeight(viewportHeight: 600, isStreaming: true) == 300)
        #expect(ChatScrollLogic.followTailHeight(viewportHeight: 600, isStreaming: false) == 0)
        #expect(ChatScrollLogic.followTailHeight(viewportHeight: 0, isStreaming: true) == 0)
    }

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

    // MARK: - «Приклеенность» якоря (прокрутка нужна только при дрейфе)

    @Test("Якорь у нижней кромки вьюпорта — приклеен, прокрутка не нужна")
    func anchorGluedNearBottom() {
        let viewport = CGRect(x: 0, y: 0, width: 800, height: 600)
        #expect(ChatScrollLogic.anchorIsGlued(
            bottomFrame: CGRect(x: 0, y: 596, width: 800, height: 4),
            viewport: viewport
        ))
        #expect(ChatScrollLogic.anchorIsGlued(
            bottomFrame: CGRect(x: 0, y: 599, width: 800, height: 1),
            viewport: viewport
        ))
    }

    @Test("Якорь дрейфует ниже вьюпорта — нужна прокрутка")
    func anchorDriftedIsNotGlued() {
        let viewport = CGRect(x: 0, y: 0, width: 800, height: 600)
        #expect(!ChatScrollLogic.anchorIsGlued(
            bottomFrame: CGRect(x: 0, y: 620, width: 800, height: 4),
            viewport: viewport
        ))
        #expect(!ChatScrollLogic.anchorIsGlued(
            bottomFrame: CGRect(x: 0, y: 590, width: 800, height: 1),
            viewport: viewport
        ))
    }

    @Test("Пустые фреймы — не приклеены (без действий)")
    func emptyFramesNotGlued() {
        let viewport = CGRect(x: 0, y: 0, width: 800, height: 600)
        #expect(!ChatScrollLogic.anchorIsGlued(
            bottomFrame: .zero,
            viewport: viewport
        ))
        #expect(!ChatScrollLogic.anchorIsGlued(
            bottomFrame: CGRect(x: 0, y: 596, width: 800, height: 4),
            viewport: .zero
        ))
    }

    @Test("Интервалы подавления и коалесценции — разумные")
    func suppressionIntervalsAreReasonable() {
        #expect(ChatScrollLogic.userScrollSuppression >= 0.4)
        #expect(ChatScrollLogic.minScrollInterval >= 0.03)
        #expect(ChatScrollLogic.coalesceNanoseconds >= 8_000_000)
        #expect(ChatScrollLogic.upwardReadingProtection >= 2.0)
    }

    @Test("Чтение вверх подавляет автопрокрутку вниз")
    func upwardReadingSuppressesAutoScroll() {
        let now = Date()
        #expect(ChatScrollLogic.shouldSuppressAutoScroll(
            lastWheelAt: now.addingTimeInterval(-1),
            lastWheelDirection: .up,
            now: now
        ))
        // Недавно, но листали вниз — подавления нет.
        #expect(!ChatScrollLogic.shouldSuppressAutoScroll(
            lastWheelAt: now.addingTimeInterval(-1),
            lastWheelDirection: .down,
            now: now
        ))
        // Листали вверх, но давно — защита истекла.
        #expect(!ChatScrollLogic.shouldSuppressAutoScroll(
            lastWheelAt: now.addingTimeInterval(-10),
            lastWheelDirection: .up,
            now: now
        ))
        // Никогда не листали — подавления нет.
        #expect(!ChatScrollLogic.shouldSuppressAutoScroll(
            lastWheelAt: .distantPast,
            lastWheelDirection: nil,
            now: now
        ))
    }
}
