import Foundation

/// Text accumulator for ONE web-chat driver turn (user directive 2026-09-11:
/// "всё что записалось от модели стирать НЕЛЬЗЯ — только дополнять").
///
/// The vendor streams SNAPSHOT text: each poll delivers the full current
/// message, not deltas. Within one generation a growing snapshot must extend
/// the block, not duplicate it; across tool rounds each new message starts a
/// fresh block; the FINAL answer appends after everything without erasing
/// earlier thinking/answers.
final class WebTurnTextAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    /// Closed blocks (thinking prose, post-tool answers) — never modified again.
    private var closedBlocks: [String] = []
    /// The in-flight snapshot block: grows by extension detection.
    private var currentSnapshot = ""

    /// Absorb a streaming snapshot. Returns the full display text:
    /// closed blocks + the (possibly extended) current snapshot.
    ///
    /// Vendors re-render markdown mid-stream (live 2026-09-12: Kimi rewrites
    /// already-shown text — "**`TZ-Bezdna" becomes "TZ-Bezdna-v3.md" — so a
    /// strict hasPrefix fails on nearly every poll). Without draft detection
    /// each poll became its own block (56 blocks in one turn). Drafts of the
    /// SAME bubble are therefore adopted/merged; only genuinely different
    /// text (low shared head) starts a fresh block. Within a round the
    /// longest draft wins — never shrinks (append-only).
    func absorb(_ snapshot: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        let snap = snapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !snap.isEmpty else { return displayTextLocked() }
        let cur = currentSnapshot
        if cur.isEmpty {
            currentSnapshot = snap
            return displayTextLocked()
        }
        if snap == cur { return displayTextLocked() }
        // Pure growth: the snapshot starts with what we already have.
        if snap.hasPrefix(cur) {
            currentSnapshot = snap
            return displayTextLocked()
        }
        // Regression/rewind (transient poll artifact): keep the longer text.
        if cur.hasPrefix(snap) { return displayTextLocked() }
        // Growth with a new head (status/header prepended): adopt the longer
        // text that fully contains what we have — no duplication.
        if snap.contains(cur) {
            currentSnapshot = snap
            return displayTextLocked()
        }
        // Re-rendered draft of the same bubble (shared head, edited tail):
        // adopt the latest draft instead of duplicating it as a new block.
        if snap.count > cur.count, Self.isSameDraft(old: cur, new: snap) {
            currentSnapshot = snap
            return displayTextLocked()
        }
        // Partial tail overlap (head rewritten, tail resynced): graft only
        // the genuinely new tail.
        if let tail = Self.novelSuffix(of: snap, after: cur) {
            currentSnapshot = cur + tail
            return displayTextLocked()
        }
        // Genuinely different text: the vendor moved to a new message —
        // close the old block, start fresh.
        closedBlocks.append(cur)
        currentSnapshot = snap
        return displayTextLocked()
    }

    /// Two snapshots are drafts of the SAME vendor message when most of the
    /// shorter's head survives in the longer (markdown re-render edits the
    /// tail). Threshold 0.5 keeps distinct same-round notes apart ("Часть
    /// 2/7…" vs "Часть 3/7…" share only "Часть " ≈ 0.1).
    private static func isSameDraft(old: String, new: String, threshold: Double = 0.5) -> Bool {
        guard !old.isEmpty else { return true }
        let common = old.commonPrefix(with: new).count
        return Double(common) / Double(old.count) >= threshold
    }

    /// Longest suffix of `cur` that is also a prefix of `snap` (bounded
    /// search) — returns the novel tail of `snap` past the overlap, or nil.
    private static func novelSuffix(of snap: String, after cur: String,
                                   minOverlap: Int = 32, maxSearch: Int = 2000) -> String? {
        let maxK = min(cur.count, snap.count, maxSearch)
        guard maxK >= minOverlap else { return nil }
        var k = maxK
        while k >= minOverlap {
            if snap.hasPrefix(String(cur.suffix(k))) { return String(snap.dropFirst(k)) }
            k -= 1
        }
        return nil
    }

    /// Absorb the FINAL answer: it lands as its own trailing block, keeping
    /// everything streamed before it (thinking, earlier tool-round answers).
    /// If it continues the in-flight snapshot (including a re-rendered
    /// draft), merge instead of duplicating.
    func absorbFinal(_ answer: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        let ans = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ans.isEmpty else { return displayTextLocked() }
        let cur = currentSnapshot
        if cur.isEmpty {
            currentSnapshot = ans
            return displayTextLocked()
        }
        // Same generation grown to completion → the snapshot IS the answer.
        if ans == cur || ans.hasPrefix(cur) || ans.contains(cur) {
            currentSnapshot = ans
            return displayTextLocked()
        }
        if cur.hasPrefix(ans) { return displayTextLocked() }
        if ans.count > cur.count, Self.isSameDraft(old: cur, new: ans) {
            currentSnapshot = ans
            return displayTextLocked()
        }
        if let tail = Self.novelSuffix(of: ans, after: cur) {
            currentSnapshot = cur + tail
            return displayTextLocked()
        }
        closedBlocks.append(cur)
        currentSnapshot = ans
        return displayTextLocked()
    }

    /// Close the in-flight block (a tool round completed; the post-tool
    /// answer must start a fresh block, not graft onto the previous text).
    func closeBlock() {
        lock.lock()
        defer { lock.unlock() }
        guard !currentSnapshot.isEmpty else { return }
        closedBlocks.append(currentSnapshot)
        currentSnapshot = ""
    }

    private func displayTextLocked() -> String {
        (closedBlocks + [currentSnapshot])
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n---\n\n")
    }
}
