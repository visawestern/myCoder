import Testing
import Foundation
@testable import myCoder

@Suite("Message Row Layout")
struct MessageRowLayoutTests {

    @Test("User messages align to the trailing edge like Telegram")
    func userMessagesTrailing() {
        #expect(MessageRowLayoutLogic.isTrailing(role: .user))
        #expect(!MessageRowLayoutLogic.isTrailing(role: .assistant))
        #expect(!MessageRowLayoutLogic.isTrailing(role: .system))
    }

    @Test("User bubbles are width-capped so they read as chat bubbles")
    func userBubbleWidthCapped() {
        #expect(MessageRowLayoutLogic.userBubbleMaxWidth >= 320)
        #expect(MessageRowLayoutLogic.userBubbleMaxWidth <= 560)
    }

    @Test("Action bar hugs the bubble with tight spacing")
    func actionBarSpacingTight() {
        #expect(MessageRowLayoutLogic.actionBarSpacing <= 6)
    }

    @Test("MessageRow uses the layout logic for both roles")
    func messageRowWiresLayoutLogic() throws {
        let source = try sourceText("myCoder/Sources/Views/Components/MessageRowView.swift")
        #expect(source.contains("MessageRowLayoutLogic.isTrailing"))
        #expect(source.contains("MessageRowLayoutLogic.userBubbleMaxWidth"))
        // Old detached action bar pattern (Spacer pushing actions to the far edge) must be gone.
        #expect(!source.contains("Spacer(minLength: 0)\n                        messageActions"))
    }

    private func sourceText(_ relativePath: String) throws -> String {
        try RepoRoot.sourceText(relativePath)
    }
}
