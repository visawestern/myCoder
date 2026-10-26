import Testing
@testable import myCoder

@Suite("Input Layout")
struct InputLayoutTests {
    
    @Test("Message input panel uses compact height budget")
    func compactHeightBudget() {
        #expect(InputLayout.textMaxHeight <= 88)
        #expect(InputLayout.textMinHeight >= 20)
        #expect(InputLayout.textLineLimit <= 5)
    }
    
    @Test("Centered card max width matches ZCode reference")
    func cardMaxWidth() {
        #expect(InputLayout.cardMaxWidth == 520)
    }

    @Test("Compact single-line prompt uses tight height")
    func compactSingleLineHeight() {
        #expect(InputLayout.compactTextHeight == 36)
        #expect(InputLayout.compactTextHeight <= InputLayout.textMaxHeight)
    }
}
