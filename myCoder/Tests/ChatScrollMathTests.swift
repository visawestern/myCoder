import Foundation
import Testing
@testable import myCoder

@Suite("ChatScrollMath — чистая математика прокрутки")
struct ChatScrollMathTests {

    @Test("maxOffset не бывает отрицательным")
    func maxOffsetNeverNegative() {
        #expect(ChatScrollMath.maxOffset(contentHeight: 100, viewportHeight: 200) == 0)
        #expect(ChatScrollMath.maxOffset(contentHeight: 200, viewportHeight: 200) == 0)
        #expect(ChatScrollMath.maxOffset(contentHeight: 300, viewportHeight: 200) == 100)
    }

    @Test("targetOffset зажимается в диапазон 0…maxOffset")
    func targetOffsetClamps() {
        // Вниз от верха.
        #expect(ChatScrollMath.targetOffset(current: 0, delta: 50, maxOffset: 200) == 50)
        // Вверх от низа — не уходит за 0.
        #expect(ChatScrollMath.targetOffset(current: 50, delta: -500, maxOffset: 200) == 0)
        // Вниз за предел — зажимается к maxOffset.
        #expect(ChatScrollMath.targetOffset(current: 180, delta: 500, maxOffset: 200) == 200)
        // maxOffset = 0 — всегда 0.
        #expect(ChatScrollMath.targetOffset(current: 10, delta: -10, maxOffset: 0) == 0)
        #expect(ChatScrollMath.targetOffset(current: 10, delta: 10, maxOffset: 0) == 0)
    }

    @Test("isAtBottom / isAtTop с допуском")
    func edgeFlags() {
        #expect(ChatScrollMath.isAtBottom(offset: 199, maxOffset: 200))
        #expect(!ChatScrollMath.isAtBottom(offset: 180, maxOffset: 200))
        #expect(ChatScrollMath.isAtTop(offset: 0))
        #expect(ChatScrollMath.isAtTop(offset: 0.5))
        #expect(!ChatScrollMath.isAtTop(offset: 5))
    }
}
