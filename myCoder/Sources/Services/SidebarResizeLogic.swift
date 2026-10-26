import Foundation

/// Pure, testable logic for sidebar resize (plan Раздел 11 Блок 1).
enum SidebarResizeLogic {
    static let defaultWidth: Double = 260
    static let minWidth: Double = 200
    static let maxWidth: Double = 420

    /// Clamp a proposed width to the allowed bounds.
    static func clamp(_ width: Double, min: Double = minWidth, max: Double = maxWidth) -> Double {
        Swift.min(max, Swift.max(min, width))
    }

    /// Apply a drag translation to the current width and return the clamped result.
    static func applyDrag(current width: Double, translation: Double, min: Double = minWidth, max: Double = maxWidth) -> Double {
        clamp(width + translation, min: min, max: max)
    }

    /// Reset to the default width.
    static func reset() -> Double { defaultWidth }
}
