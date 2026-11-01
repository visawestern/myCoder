import AppKit
import Foundation
import SwiftUI

/// Pure offset math for the chat scroller. Kept separate from AppKit so the
/// clamping rules (the part that decides whether a wheel tick can move at all)
/// are covered by tests.
enum ChatScrollMath {
    /// Target offset for a relative scroll, clamped to the real content range.
    /// A negative result would bounce past the top; anything past `maxOffset`
    /// would be clamped by NSScrollView anyway, but doing it here lets the API
    /// report the applied delta honestly instead of echoing the requested one.
    static func targetOffset(current: CGFloat, delta: CGFloat, maxOffset: CGFloat) -> CGFloat {
        let maxY = max(0, maxOffset)
        return min(max(0, current + delta), maxY)
    }

    static func maxOffset(contentHeight: CGFloat, viewportHeight: CGFloat) -> CGFloat {
        max(0, contentHeight - viewportHeight)
    }

    static func isAtBottom(offset: CGFloat, maxOffset: CGFloat, slack: CGFloat = 1) -> Bool {
        offset >= max(0, maxOffset) - slack
    }

    static func isAtTop(offset: CGFloat, slack: CGFloat = 1) -> Bool {
        offset <= slack
    }
}

/// One observed scroll position (recorded on every clip-view bounds change).
struct ChatScrollSample: Equatable {
    let at: Date
    let offsetY: CGFloat
    let maxOffsetY: CGFloat
}

/// Live handle to the chat's `NSScrollView`.
///
/// SwiftUI's `ScrollView` exposes neither its scroll view nor its offset, so
/// the local API and the scroll diagnostics need a bridge: a zero-size probe
/// inside the scroll content climbs to the enclosing `NSScrollView` and
/// registers it here. Nothing in this class publishes SwiftUI state — samples
/// are written to a plain array so observing the scroll cannot invalidate the
/// view tree (the old preference-based reporters did exactly that on every
/// frame and made long chats stutter).
@MainActor
final class ChatScrollBridge {
    static let shared = ChatScrollBridge()

    private init() {}

    private(set) weak var scrollView: NSScrollView?
    private(set) var attachedAt: Date?
    private(set) var attachAttempts = 0
    private var monitoringSource: String?
    private var boundsObserver: NSObjectProtocol?
    private var anchorJumper: ((String, UnitPoint) -> Void)?

    /// Ring buffer of the last clip-view positions. `GET /api/scroll?samples=1`
    /// returns it, which makes a "stopped and then jumped" symptom visible as a
    /// long flat run followed by one large delta.
    private(set) var samples: [ChatScrollSample] = []
    private let sampleLimit = 400
    private(set) var lastCommand: [String: Any]?
    /// Wheel events observed by the app's own local monitor (installed by
    /// ChatPanelView). Lets the diagnostics confirm that a reproduction posted
    /// events that actually reached the app.
    private(set) var wheelEventsObserved = 0
    private(set) var scrollMonitorInstalled = false

    func noteWheelEvent() {
        wheelEventsObserved += 1
    }

    func noteScrollMonitorInstalled() {
        scrollMonitorInstalled = true
    }

    /// Diagnostic: what view is under the pointer (or under a given screen
    /// point)? Used to find who intercepts scroll-wheel events.
    func hitChain(atScreenPoint screenPoint: NSPoint? = nil) -> [String: Any] {
        let point = screenPoint ?? NSEvent.mouseLocation
        guard let window = NSApp.keyWindow
                ?? NSApp.mainWindow
                ?? NSApp.windows.first(where: { $0.isVisible }),
              let content = window.contentView else {
            return ["error": "no window"]
        }
        let windowPoint = window.convertPoint(fromScreen: point)
        let local = content.convert(windowPoint, from: nil)
        let hit = content.hitTest(local)
        var chain: [String] = []
        var textUnderPointer = false
        var current: NSView? = hit
        while let view = current {
            chain.append(String(describing: type(of: view)))
            if let textView = view as? NSTextView,
               (textView.isEditable || textView.isSelectable) {
                textUnderPointer = true
            }
            current = view.superview
        }
        return [
            "screen": ["x": Double(point.x), "y": Double(point.y)],
            "local": ["x": Double(local.x), "y": Double(local.y)],
            "hit": hit.map { String(describing: type(of: $0)) } ?? "nil",
            "textUnderPointer": textUnderPointer,
            "chain": chain
        ]
    }

    // MARK: - Attachment

    /// Walk up from a view that lives inside the chat content until the
    /// enclosing NSScrollView is found. Called from the probe on insertion.
    /// Uses AppKit's `enclosingScrollView` first (it knows the real hierarchy);
    /// the manual walk is a fallback for hosting-view layouts where that
    /// property is not populated yet.
    func attach(from view: NSView) {
        attachAttempts += 1
        if let scrollView = view.enclosingScrollView {
            bind(scrollView)
            return
        }
        var candidate: NSView? = view.superview
        var path: [String] = []
        while let current = candidate {
            path.append(String(describing: type(of: current)))
            if let scrollView = current as? NSScrollView {
                bind(scrollView)
                return
            }
            candidate = current.superview
        }
        lastCommand = [
            "ok": false,
            "source": "attach",
            "error": "no NSScrollView found on the probe's superview chain",
            "probe": String(describing: type(of: view)),
            "superviewPath": path
        ]
    }

    private func bind(_ scrollView: NSScrollView) {
        guard self.scrollView !== scrollView else { return }
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
        self.scrollView = scrollView
        monitoringSource = "probe"
        attachedAt = Date()
        scrollView.contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.recordSample() }
        }
        recordSample()
    }

    func detach() {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
        boundsObserver = nil
        scrollView = nil
        samples.removeAll()
        attachedAt = nil
    }

    /// The ScrollViewReader proxy lets the API jump to a row by id (message
    /// anchors), which raw NSScrollView offsets cannot resolve.
    func registerAnchorJumper(_ jump: @escaping (String, UnitPoint) -> Void) {
        anchorJumper = jump
    }

    func clearAnchorJumper() {
        anchorJumper = nil
    }

    // MARK: - State

    struct Snapshot {
        var offsetY: CGFloat
        var maxOffsetY: CGFloat
        var viewportHeight: CGFloat
        var documentHeight: CGFloat
        var isAtBottom: Bool
        var isAtTop: Bool

        static let empty = Snapshot(
            offsetY: 0,
            maxOffsetY: 0,
            viewportHeight: 0,
            documentHeight: 0,
            isAtBottom: true,
            isAtTop: true
        )

        var json: [String: Any] {
            [
                "offsetY": Double(offsetY),
                "maxOffsetY": Double(maxOffsetY),
                "viewportHeight": Double(viewportHeight),
                "documentHeight": Double(documentHeight),
                "isAtBottom": isAtBottom,
                "isAtTop": isAtTop
            ]
        }
    }

    private func snapshot(for scrollView: NSScrollView) -> Snapshot {
        guard let document = scrollView.documentView else { return .empty }
        let clip = scrollView.contentView
        let viewport = clip.bounds.height
        let documentHeight = document.frame.height
        let maxOffsetY = ChatScrollMath.maxOffset(
            contentHeight: documentHeight,
            viewportHeight: viewport
        )
        let offsetY = clip.bounds.origin.y
        return Snapshot(
            offsetY: offsetY,
            maxOffsetY: maxOffsetY,
            viewportHeight: viewport,
            documentHeight: documentHeight,
            isAtBottom: ChatScrollMath.isAtBottom(offset: offsetY, maxOffset: maxOffsetY),
            isAtTop: ChatScrollMath.isAtTop(offset: offsetY)
        )
    }

    private func snapshot() -> Snapshot {
        guard let scrollView else { return .empty }
        return snapshot(for: scrollView)
    }

    // MARK: - Window fallback

    /// When no probe has attached (e.g. the lazy stack has not materialized
    /// the bottom sentinel yet), find the most likely chat scroll view by
    /// scanning the key window's view tree. The chat scroll view is the
    /// largest visible vertical scroll container. This keeps the API usable
    /// in every scroll position — the probe remains the preferred source.
    private func windowScrollViews() -> [(view: NSScrollView, area: CGFloat, documentHeight: CGFloat, frame: CGRect)] {
        guard let window = NSApp.keyWindow
                ?? NSApp.mainWindow
                ?? NSApp.windows.first(where: { $0.isVisible }) else {
            return []
        }
        var found: [NSScrollView] = []
        func walk(_ view: NSView) {
            if let scrollView = view as? NSScrollView {
                found.append(scrollView)
            }
            for subview in view.subviews {
                walk(subview)
            }
        }
        if let contentView = window.contentView {
            walk(contentView)
        }
        return found.compactMap { scrollView in
            guard let document = scrollView.documentView else { return nil }
            let viewport = scrollView.contentView.bounds.height
            let documentHeight = document.frame.height
            guard viewport > 50, documentHeight > viewport + 1 else { return nil }
            let frame = scrollView.frame
            let area = frame.width * viewport
            return (scrollView, area, documentHeight, frame)
        }
        .sorted { $0.area > $1.area }
    }

    private func resolvedScrollView() -> NSScrollView? {
        let candidates = windowScrollViews()
        let wide = candidates.first(where: { $0.frame.width >= 400 })
        if let current = scrollView, current.window != nil {
            // If a wider chat scroll view exists and we are bound to a narrow
            // sidebar (or any smaller candidate), rebind to the chat view.
            if let wide, current !== wide.view {
                bind(wide.view)
                monitoringSource = "window-scan"
                return wide.view
            }
            let stillValid = candidates.contains { $0.view === current }
            if stillValid {
                return current
            }
        }
        if let wide {
            return wide.view
        }
        return candidates.first?.view
    }

    /// Ensure the sample recorder is attached to the resolved scroll view. The
    /// probe is preferred; when it has not attached (e.g. the lazy stack has
    /// not materialized), bind the window-scanned candidate so wheel
    /// reproductions record offset samples too.
    func ensureMonitoring() {
        guard scrollView == nil else { return }
        guard let resolved = resolvedScrollView() else { return }
        bind(resolved)
        monitoringSource = "window-scan"
        lastCommand = [
            "ok": true,
            "source": "monitor",
            "note": "bound via window-scan (probe did not attach)",
            "documentHeight": Double(snapshot(for: resolved).documentHeight)
        ]
    }

    private func recordSample() {
        guard scrollView != nil else { return }
        let current = snapshot()
        if let last = samples.last,
           last.offsetY == current.offsetY,
           last.maxOffsetY == current.maxOffsetY {
            return
        }
        samples.append(ChatScrollSample(
            at: Date(),
            offsetY: current.offsetY,
            maxOffsetY: current.maxOffsetY
        ))
        if samples.count > sampleLimit {
            samples.removeFirst(samples.count - sampleLimit)
        }
    }

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

/// Zero-size probe placed inside the chat `ScrollView` content. On insertion
/// it climbs to the enclosing NSScrollView and hands it to the bridge.
struct ChatScrollProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ChatScrollProbeView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        ChatScrollBridge.shared.attach(from: nsView)
    }
}

final class ChatScrollProbeView: NSView {
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { .zero }

    private func retryAttach() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            let attached = ChatScrollBridge.shared.scrollView != nil
            guard !attached else { return }
            ChatScrollBridge.shared.attach(from: self)
        }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        guard superview != nil else { return }
        Task { @MainActor in
            ChatScrollBridge.shared.attach(from: self)
        }
        retryAttach()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        Task { @MainActor in
            ChatScrollBridge.shared.attach(from: self)
        }
        retryAttach()
    }
}
