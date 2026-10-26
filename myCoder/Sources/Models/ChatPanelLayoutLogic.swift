import Foundation
import CoreGraphics
import SwiftUI

enum ChatPanelLayoutLogic {
    static let emptyStateStackSpacing: CGFloat = 24

    static func shouldUseCenteredInput(messageCount: Int) -> Bool {
        messageCount == 0
    }
}

enum MyCoderLogoSpec {
    static let markText = "myCoder code mark"
    static let accentHex = "6EE7F2"

    static var accentColor: Color {
        Color(red: 0.431, green: 0.906, blue: 0.949)
    }
}
