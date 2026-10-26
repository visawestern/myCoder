import SwiftUI

enum SpoilerExpandLogic {
    static let contentMaxHeight: CGFloat = 280

    /// Number of lines shown as a collapsed preview below the spoiler title.
    static let collapsedPreviewLineCount: Int = 4

    /// Approximate line height used to compute the collapsed preview height.
    static let collapsedLineHeight: CGFloat = 18

    static var animation: Animation {
        .spring(response: 0.28, dampingFraction: 0.9)
    }

    /// Height fits the measured content; caps at max, falls back to max until measured.
    static func contentHeight(isExpanded: Bool, measuredHeight: CGFloat) -> CGFloat {
        guard isExpanded else { return 0 }
        guard measuredHeight > 0 else { return contentMaxHeight }
        return min(measuredHeight, contentMaxHeight)
    }

    static func contentOpacity(isExpanded: Bool) -> Double {
        isExpanded ? 1 : 0
    }

    /// Height of the collapsed preview (a few lines) when the message is done.
    static func collapsedPreviewHeight(lineHeight: CGFloat = collapsedLineHeight) -> CGFloat {
        lineHeight * CGFloat(collapsedPreviewLineCount)
    }
}
