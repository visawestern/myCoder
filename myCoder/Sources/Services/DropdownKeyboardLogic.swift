import Foundation

/// Pure keyboard-navigation logic for the input command dropdown
/// (plan Раздел 6 Блок 2 п.14). The view maps key events to these transitions;
/// keeping it here makes selection/wrap behavior testable.
enum DropdownKeyboardLogic {
    /// Move the highlight down, wrapping to the top past the last item.
    static func moveDown(current: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (current + 1) % count
    }

    /// Move the highlight up, wrapping to the bottom past the first item.
    static func moveUp(current: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (current - 1 + count) % count
    }

    /// Clamp a highlight index into range (e.g. after the list shrank on filter).
    static func clamp(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return Swift.min(Swift.max(0, index), count - 1)
    }

    /// The item index to commit on Enter/Tab, or nil if the list is empty.
    static func commitIndex(highlight: Int, count: Int) -> Int? {
        count > 0 ? clamp(highlight, count: count) : nil
    }
}
