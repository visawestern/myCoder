import Testing
import Foundation
@testable import myCoder

/// The navigator highlight must survive LazyVStack recycling and must name the
/// UPPER message when the viewport sits in the gap between two rows. The old
/// resolver only saw frames reported by the current layout pass; off-screen
/// rows disappeared from the map and the navigator showed no active number.
@Suite("Chat navigator layout — persistent frames and upper-row highlight")
struct ChatNavigatorLayoutLogicTests {

    private func entry(_ id: String, _ ordinal: Int) -> UserMessageIndexEntry {
        UserMessageIndexEntry(id: id, ordinal: ordinal, preview: id)
    }

    private let entries = [
        UserMessageIndexEntry(id: "u1", ordinal: 1, preview: "first"),
        UserMessageIndexEntry(id: "u2", ordinal: 2, preview: "second"),
        UserMessageIndexEntry(id: "u3", ordinal: 3, preview: "third"),
    ]

    private let frames: [String: CGRect] = [
        "u1": CGRect(x: 0, y: 0, width: 600, height: 100),
        "u2": CGRect(x: 0, y: 400, width: 600, height: 100),
        "u3": CGRect(x: 0, y: 800, width: 600, height: 100),
    ]

    @Test("Viewport inside a row highlights that row")
    func insideRow() {
        let visible = CGRect(x: 0, y: 430, width: 600, height: 300)
        #expect(ChatNavigatorLayoutLogic.currentUserMessageID(
            visibleRect: visible,
            frames: frames,
            entries: entries
        ) == "u2")
    }

    @Test("Viewport in the gap between rows highlights the UPPER row")
    func gapHighlightsUpper() {
        // The viewport middle sits between u1 (ends at 100) and u2 (starts at
        // 400) — the assistant answer occupies that gap.
        let visible = CGRect(x: 0, y: 150, width: 600, height: 300)
        #expect(ChatNavigatorLayoutLogic.currentUserMessageID(
            visibleRect: visible,
            frames: frames,
            entries: entries
        ) == "u1")
    }

    @Test("Viewport above the first row highlights the first row")
    func aboveFirst() {
        let visible = CGRect(x: 0, y: 0, width: 600, height: 60)
        // Probe = 30 is above u1's measured band only if u1 starts lower; with
        // the standard map it is inside u1. Use a shifted map for this case.
        let shifted = ["u1": CGRect(x: 0, y: 200, width: 600, height: 100)]
        #expect(ChatNavigatorLayoutLogic.currentUserMessageID(
            visibleRect: visible,
            frames: shifted,
            entries: entries
        ) == "u1")
    }

    @Test("Viewport below the last row highlights the last row")
    func belowLast() {
        let visible = CGRect(x: 0, y: 1_500, width: 600, height: 300)
        #expect(ChatNavigatorLayoutLogic.currentUserMessageID(
            visibleRect: visible,
            frames: frames,
            entries: entries
        ) == "u3")
    }

    @Test("Entry order, not dictionary order, decides the upper row")
    func entryOrderWins() {
        let visible = CGRect(x: 0, y: 250, width: 600, height: 100)
        let shuffled = [
            "u3": CGRect(x: 0, y: 800, width: 600, height: 100),
            "u1": CGRect(x: 0, y: 0, width: 600, height: 100),
            "u2": CGRect(x: 0, y: 400, width: 600, height: 100),
        ]
        #expect(ChatNavigatorLayoutLogic.currentUserMessageID(
            visibleRect: visible,
            frames: shuffled,
            entries: entries
        ) == "u1")
    }

    @Test("No measured rows means no highlight")
    func noFrames() {
        #expect(ChatNavigatorLayoutLogic.currentUserMessageID(
            visibleRect: CGRect(x: 0, y: 0, width: 600, height: 300),
            frames: [:],
            entries: entries
        ) == nil)
    }

    @Test("Merging keeps frames LazyVStack stopped reporting and drops removed rows")
    func mergeKeepsOffscreenRows() {
        let stored = [
            "u1": CGRect(x: 0, y: 0, width: 600, height: 100),
            "u2": CGRect(x: 0, y: 400, width: 600, height: 100),
        ]
        let reported = [
            "u2": CGRect(x: 0, y: 400, width: 600, height: 100),
            "u3": CGRect(x: 0, y: 800, width: 600, height: 100),
        ]
        let merged = ChatNavigatorLayoutLogic.merged(
            stored: stored,
            reported: reported,
            validIDs: ["u1", "u2", "u3"]
        )
        #expect(merged.keys.sorted() == ["u1", "u2", "u3"])

        let pruned = ChatNavigatorLayoutLogic.merged(
            stored: merged,
            reported: [:],
            validIDs: ["u2", "u3"]
        )
        #expect(pruned.keys.sorted() == ["u2", "u3"])
    }

    @Test("Prepending a page shifts every stored frame by the same delta")
    func shiftMovesAllFrames() {
        let shifted = ChatNavigatorLayoutLogic.shifted(frames, by: 240)
        #expect(shifted["u1"]?.minY == 240)
        #expect(shifted["u2"]?.minY == 640)
        #expect(shifted["u3"]?.minY == 1_040)
    }

    @Test("A common measured row reveals the prepend shift")
    func detectsShiftFromAnyCommonRow() {
        let reported = [
            "u2": CGRect(x: 0, y: 640, width: 600, height: 100),
        ]
        #expect(ChatNavigatorLayoutLogic.shift(from: frames, reported: reported) == 240)
    }
}
