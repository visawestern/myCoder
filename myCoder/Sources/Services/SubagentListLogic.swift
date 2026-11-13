import Foundation
import CoreGraphics

/// Sizing and navigation rules for the right-panel sub-agent list.
///
/// Input: the number of child chats and their fixed row height. Output: how
/// many rows are visible (max five), the exact scroll-viewport height, and
/// whether a scrollbar is needed.
///
/// Dependencies: CoreGraphics for CGFloat only. Pure, no UI, no AppState.
enum SubagentListLogic {
    /// User directive 2026-11-13: never show more than five sub-agent rows;
    /// the rest live in a fixed-height scroll list.
    static let maxVisibleRows = 5

    /// One row has a fixed height so the list can never grow with long titles
    /// (titles wrap to two lines inside this height).
    static let rowHeight: CGFloat = 44

    /// Number of rows to reserve height for.
    ///
    /// - Parameter total: all child sessions of the current parent.
    /// - Returns: 0…5.
    static func visibleCount(total: Int) -> Int {
        min(max(0, total), maxVisibleRows)
    }

    /// Exact height of the list viewport.
    ///
    /// - Parameters:
    ///   - total: all child sessions of the current parent.
    ///   - rowHeight: fixed row height (injectable for tests).
    /// - Returns: `visibleCount × rowHeight`, 0 when empty.
    static func listHeight(total: Int, rowHeight: CGFloat = SubagentListLogic.rowHeight) -> CGFloat {
        CGFloat(visibleCount(total: total)) * rowHeight
    }

    /// Whether the list needs its own scrollbar.
    ///
    /// - Parameter total: all child sessions of the current parent.
    /// - Returns: true when more than five rows exist.
    static func shouldScroll(total: Int) -> Bool {
        total > maxVisibleRows
    }

    /// Which parent's children the panel must list for the selected chat.
    ///
    /// A parent chat lists its own children. A child chat keeps showing its
    /// SIBLINGS instead of emptying the panel (which happened before: opening
    /// a sub-agent chat made the section disappear).
    ///
    /// - Parameter session: currently selected chat.
    /// - Returns: id whose child sessions should be loaded.
    static func childrenParentID(for session: ChatSession) -> String {
        session.parentSessionID ?? session.id
    }

    /// Resolve the parent chat for the "back" breadcrumb.
    ///
    /// - Parameters:
    ///   - session: currently selected chat.
    ///   - sessions: top-level chats currently in memory.
    /// - Returns: the parent session, or nil for a normal chat/orphan.
    static func parentSession(
        for session: ChatSession,
        in sessions: [ChatSession]
    ) -> ChatSession? {
        guard let parentID = session.parentSessionID else { return nil }
        return sessions.first { $0.id == parentID }
    }
}
