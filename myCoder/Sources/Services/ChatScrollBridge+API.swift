import AppKit
import Foundation
import SwiftUI

extension ChatScrollBridge {
    /// JSON state for `/api/scroll` (GET) and the `chat.scrollState` action.
    func state(includeSamples: Bool = false, sampleLimit: Int = 60) -> [String: Any] {
        if includeSamples || scrollView == nil {
            ensureMonitoring()
        }
        let resolved = resolvedScrollView()
        let snap: Snapshot = resolved.map { snapshot(for: $0) } ?? .empty
        var result: [String: Any] = [
            "ok": resolved != nil,
            "attached": scrollView != nil,
            "monitoring": scrollView != nil ? (monitoringSource ?? "probe") : "none",
            "resolvedBy": resolved != nil ? (scrollView != nil ? (monitoringSource ?? "probe") : "window-scan") : "none",
            "window": resolved?.window?.title ?? "",
            "scroll": snap.json,
            "samplesRecorded": samples.count,
            "wheelEventsObserved": wheelEventsObserved,
            "scrollMonitorInstalled": scrollMonitorInstalled,
            "attachAttempts": attachAttempts,
            "lastCommand": lastCommand ?? [:]
        ]
        if resolved == nil {
            result["error"] = "no chat scroll view found (is a chat visible with messages?)"
        }
        result["windowCandidates"] = windowScrollViews().prefix(8).map { candidate in
            [
                "class": String(describing: type(of: candidate.view)),
                "area": Double(candidate.area),
                "documentHeight": Double(candidate.documentHeight),
                "frame": [
                    "x": Double(candidate.frame.minX),
                    "y": Double(candidate.frame.minY),
                    "width": Double(candidate.frame.width),
                    "height": Double(candidate.frame.height)
                ]
            ]
        }
        if includeSamples {
            let tail = samples.suffix(max(1, sampleLimit))
            result["samples"] = tail.map { sample in
                [
                    "t": sample.at.timeIntervalSince1970,
                    "y": Double(sample.offsetY),
                    "maxY": Double(sample.maxOffsetY)
                ]
            }
        }
        return result
    }

    // MARK: - Scrolling

    private func apply(offset: CGFloat, source: String) -> [String: Any] {
        guard let scrollView = resolvedScrollView() else {
            return ["ok": false, "error": "no chat scroll view found (is a chat visible with messages?)"]
        }
        let before = snapshot(for: scrollView)
        let clip = scrollView.contentView
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: offset))
        scrollView.reflectScrolledClipView(clip)
        let after = snapshot(for: scrollView)
        let report: [String: Any] = [
            "ok": true,
            "source": source,
            "resolvedBy": self.scrollView != nil ? "probe" : "window-scan",
            "requestedY": Double(offset),
            "before": before.json,
            "after": after.json,
            "moved": abs(after.offsetY - before.offsetY) > 0.01,
            "appliedDelta": Double(after.offsetY - before.offsetY)
        ]
        lastCommand = report
        Self.appendLog(report)
        return report
    }

    /// Scroll by a pixel delta (positive = down / later content).
    @discardableResult
    func scrollBy(pixels: CGFloat, source: String = "api") -> [String: Any] {
        guard let scrollView = resolvedScrollView() else {
            return ["ok": false, "error": "no chat scroll view found (is a chat visible with messages?)"]
        }
        let current = snapshot(for: scrollView)
        let target = ChatScrollMath.targetOffset(
            current: current.offsetY,
            delta: pixels,
            maxOffset: current.maxOffsetY
        )
        return apply(offset: target, source: source)
    }

    @discardableResult
    func scrollToTop(source: String = "api") -> [String: Any] {
        apply(offset: 0, source: source)
    }

    @discardableResult
    func scrollToBottom(source: String = "api") -> [String: Any] {
        guard let scrollView = resolvedScrollView() else {
            return ["ok": false, "error": "no chat scroll view found (is a chat visible with messages?)"]
        }
        return apply(offset: snapshot(for: scrollView).maxOffsetY, source: source)
    }

    /// Jump to a SwiftUI row id (message anchor). Uses the ScrollViewReader
    /// registered by ChatPanelView; the offset itself is not addressable by id.
    @discardableResult
    func scroll(toAnchor id: String, anchor: UnitPoint = .top) -> [String: Any] {
        guard let anchorJumper else {
            return ["ok": false, "error": "anchor jumper is not registered (no chat on screen)"]
        }
        let before = snapshot()
        anchorJumper(id, anchor)
        // scrollTo applies on the next layout pass; report the request now and
        // let the caller read the resulting offset from GET /api/scroll.
        let report: [String: Any] = [
            "ok": true,
            "source": "anchor",
            "anchor": id,
            "anchorUnitPoint": "\(anchor)",
            "before": before.json,
            "note": "scrollTo is scheduled; read GET /api/scroll after one layout pass"
        ]
        lastCommand = report
        Self.appendLog(report)
        return report
    }

    /// Post real scroll-wheel events at the centre of the chat scroll view.
    /// This is the reproduction path for "the wheel stops / jumps": the events
    /// go through AppKit's normal hit-testing and NSScrollView handling, not
    /// through a direct offset write.
    ///
    /// Events are posted asynchronously; the method returns immediately. Read
    /// `GET /api/scroll` afterwards to see how far the offset actually moved.
    @discardableResult
    func postWheel(
        pixels: Int32,
        times: Int,
        intervalMilliseconds: Int = 16,
        direction: String = "down"
    ) -> [String: Any] {
        guard let scrollView = resolvedScrollView(), let window = scrollView.window else {
            return ["ok": false, "error": "no chat scroll view found (is a chat visible with messages?)"]
        }
        guard times > 0, times <= 500 else {
            return ["ok": false, "error": "times must be 1…500"]
        }
        let rectInWindow = scrollView.convert(scrollView.bounds, to: nil)
        let screenRect = window.convertToScreen(rectInWindow)
        let mainHeight = NSScreen.main?.frame.height ?? 0
        let point = CGPoint(x: screenRect.midX, y: mainHeight - screenRect.midY)
        let signed = direction == "up" ? abs(pixels) : -abs(pixels)
        let step = max(1, intervalMilliseconds)
        let count = times

        // Bring the app to the front so the posted events land in our window
        // (the harness/terminal may own the foreground), then place the cursor
        // at the wheel point so the events hit-test against the chat scroll
        // view. A short settle after the warp is required: events posted
        // immediately can still be routed to the previous cursor region.
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.mycoder.app").first {
            app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        }
        CGWarpMouseCursorPosition(point)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            for _ in 0..<count {
                if let event = CGEvent(
                    scrollWheelEvent2Source: nil,
                    units: .pixel,
                    wheelCount: 1,
                    wheel1: signed,
                    wheel2: 0,
                    wheel3: 0
                ) {
                    event.location = point
                    // Post through the HID tap: this follows the same path as
                    // a real mouse wheel, so the app's wheel handling sees the
                    // exact same events as the user's trackpad/wheel.
                    event.post(tap: .cghidEventTap)
                }
                try? await Task.sleep(nanoseconds: UInt64(step) * 1_000_000)
            }
        }

        let report: [String: Any] = [
            "ok": true,
            "source": "wheel",
            "queued": count,
            "pixelsPerEvent": pixels,
            "direction": direction,
            "intervalMs": step,
            "point": ["x": Double(point.x), "y": Double(point.y)],
            "note": "events posted asynchronously; read GET /api/scroll for the result"
        ]
        lastCommand = report
        Self.appendLog(report)
        return report
    }

    private static func appendLog(_ report: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return }
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(stamp)] \(json)\n"
        let url = MyCoderPaths.logFile(
            name: "scroll.log",
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            handle.closeFile()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}
