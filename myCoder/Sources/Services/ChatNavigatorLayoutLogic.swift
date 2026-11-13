import Foundation
import CoreGraphics

/// Persistent content-space layout of the chat rows the navigator needs.
///
/// SwiftUI's `LazyVStack` reports frames only for rows materialised in the
/// current layout pass. Off-screen rows disappear from the preference map, so
/// the old highlight resolver returned `nil` whenever the viewport sat between
/// two user rows. This helper keeps the last known frame of every loaded row,
/// shifts the whole map when a history page is prepended, and resolves the
/// active message by the UPPER row when the viewport is in a gap.
///
/// Dependencies: Foundation/CoreGraphics only. Pure and fully testable.
enum ChatNavigatorLayoutLogic {

    /// Merge freshly reported frames into the stored map.
    ///
    /// - Parameters:
    ///   - stored: frames remembered from previous layout passes.
    ///   - reported: frames SwiftUI reported in this pass.
    ///   - validIDs: ids still present in the feed (removed rows are dropped).
    /// - Returns: merged map containing every still-valid remembered row.
    static func merged(
        stored: [String: CGRect],
        reported: [String: CGRect],
        validIDs: Set<String>
    ) -> [String: CGRect] {
        var result = stored.filter { validIDs.contains($0.key) }
        for (id, frame) in reported where validIDs.contains(id) {
            result[id] = frame
        }
        return result
    }

    /// Shift every remembered frame after a page was prepended above them.
    ///
    /// - Parameters:
    ///   - frames: content-space frames.
    ///   - delta: how far down the content moved (inserted page height).
    /// - Returns: shifted frames.
    static func shifted(_ frames: [String: CGRect], by delta: CGFloat) -> [String: CGRect] {
        guard abs(delta) > 0.01 else { return frames }
        return frames.mapValues { $0.offsetBy(dx: 0, dy: delta) }
    }

    /// Detect the prepend shift from any row present in both maps.
    ///
    /// The dedicated pagination anchor can be missing from a layout pass (the
    /// row was recycled). Any other row measured before and after the insert
    /// carries the same delta, so the map never stays stale.
    ///
    /// - Parameters:
    ///   - stored: frames from before the insert.
    ///   - reported: frames from the current pass.
    /// - Returns: vertical delta, or nil when no common row moved.
    static func shift(
        from stored: [String: CGRect],
        reported: [String: CGRect]
    ) -> CGFloat? {
        for (id, newFrame) in reported {
            guard let oldFrame = stored[id] else { continue }
            let delta = newFrame.minY - oldFrame.minY
            if abs(delta) > 0.5 { return delta }
        }
        return nil
    }

    /// Resolve the user message the reader is looking at.
    ///
    /// Rules:
    /// 1. If the viewport's middle line is inside a user row — that row.
    /// 2. If it sits in the gap between rows (a long assistant answer) — the
    ///    UPPER row, i.e. the last row whose top edge is above the probe.
    /// 3. Above all measured rows — the first row; below all — the last row.
    ///
    /// - Parameters:
    ///   - visibleRect: viewport in content coordinates.
    ///   - frames: remembered content-space frames (user rows + latest row).
    ///   - entries: session-ordered user messages.
    /// - Returns: id of the active user message, or nil when nothing is known.
    static func currentUserMessageID(
        visibleRect: CGRect?,
        frames: [String: CGRect],
        entries: [UserMessageIndexEntry]
    ) -> String? {
        guard let visible = visibleRect, visible.height > 0, !entries.isEmpty else {
            return nil
        }
        let probe = visible.midY
        var measured: [(id: String, frame: CGRect)] = []
        measured.reserveCapacity(entries.count)
        for entry in entries {
            guard let frame = frames[entry.id], frame.height > 0 else { continue }
            measured.append((entry.id, frame))
        }
        guard !measured.isEmpty else { return nil }

        for row in measured where row.frame.minY <= probe && row.frame.maxY > probe {
            return row.id
        }
        // Gap or below: the last row that starts above the probe is the upper
        // neighbour. If the probe is above every measured row, the first row
        // is the closest one.
        var upper: String?
        for row in measured where row.frame.minY <= probe {
            upper = row.id
        }
        return upper ?? measured.first?.id
    }
}
