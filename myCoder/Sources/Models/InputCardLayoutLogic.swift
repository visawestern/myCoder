import CoreGraphics
import SwiftUI

/// Layout + motion for the empty-state sci-fi input capsule.
enum InputCardLayoutLogic {
    static let contentHorizontalPadding: CGFloat = 14
    static let capsuleCornerRadius: CGFloat = 22
    static let headerExpansionTravel: CGFloat = 42
    static let footerExpansionTravel: CGFloat = 46
    static let sectionSpacing: CGFloat = 0

    static var expansionAnimation: Animation {
        .spring(response: 0.52, dampingFraction: 0.84)
    }

    static func headerExpansionOffset(progress: CGFloat, travel: CGFloat = headerExpansionTravel) -> CGFloat {
        (1 - clamped(progress)) * travel
    }

    static func footerExpansionOffset(progress: CGFloat, travel: CGFloat = footerExpansionTravel) -> CGFloat {
        -((1 - clamped(progress)) * travel)
    }

    static func sectionOpacity(progress: CGFloat) -> Double {
        Double(clamped(progress))
    }

    private static func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }
}
