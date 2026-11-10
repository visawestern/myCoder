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

    /// Offset for following the latest answer. Input is the latest message's
    /// bottom in content coordinates, viewport size and the real scroll range;
    /// output keeps that bottom at viewport centre whenever enough following
    /// space exists, otherwise clamps to the document. Depends on no UI state.
    static func followedOffset(latestContentBottom: CGFloat,
                               viewportHeight: CGFloat,
                               maxOffset: CGFloat) -> CGFloat {
        let centered = latestContentBottom - viewportHeight / 2
        return min(max(0, centered), max(0, maxOffset))
    }

    /// Whether a changed document height needs a fresh follow offset. Input is
    /// the previous pin and old/new range; output is true for both growth and
    /// replacement/shrink, but never while the reader browses older content.
    static func shouldReanchorFollowedContent(wasPinned: Bool,
                                               oldMaxOffset: CGFloat,
                                               newMaxOffset: CGFloat) -> Bool {
        wasPinned && abs(newMaxOffset - oldMaxOffset) > 1
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
    var monitoringSource: String?
    private var boundsObserver: NSObjectProtocol?
    var anchorJumper: ((String, UnitPoint) -> Void)?
    /// Called on every real offset/content change. This is the cheap
    /// replacement for per-frame SwiftUI geometry preferences: one AppKit
    /// bounds notification, and the view only mutates state when a derived
    /// value (at-bottom flag, current message id) actually changes.
    var onScroll: ((Snapshot) -> Void)?

    /// Ring buffer of the last clip-view positions. `GET /api/scroll?samples=1`
    /// returns it, which makes a "stopped and then jumped" symptom visible as a
    /// long flat run followed by one large delta.
    private(set) var samples: [ChatScrollSample] = []
    private let sampleLimit = 400
    var lastCommand: [String: Any]?
    /// Wheel events observed by the app's own local monitor (installed by
    /// ChatPanelView). Lets the diagnostics confirm that a reproduction posted
    /// events that actually reached the app.
    var wheelEventsObserved = 0
    var scrollMonitorInstalled = false

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

    func snapshot(for scrollView: NSScrollView) -> Snapshot {
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

    func snapshot() -> Snapshot {
        guard let scrollView else { return .empty }
        return snapshot(for: scrollView)
    }

    /// Текущая позиция скролла (для расчёта видимой строки и компенсации
    /// высоты при подгрузке истории).
    func currentSnapshot() -> Snapshot {
        if let scrollView, scrollView.window != nil {
            return snapshot(for: scrollView)
        }
        guard let resolved = resolvedScrollView() else { return .empty }
        return snapshot(for: resolved)
    }

    /// Поставить смещение напрямую, без SwiftUI-анимации и без записи в лог.
    /// Используется для компенсации вставки старых сообщений: контент
    /// добавляется сверху, а вьюпорт должен остаться на том же тексте.
    func setOffset(_ offset: CGFloat) {
        // Prefer the already-bound view: this runs inside a layout pass, and a
        // window-tree scan on every prepend would itself cost frames.
        guard let scrollView = (self.scrollView?.window != nil ? self.scrollView : resolvedScrollView()) else {
            return
        }
        let clip = scrollView.contentView
        let maxY = snapshot(for: scrollView).maxOffsetY
        let target = min(max(0, offset), maxY)
        guard abs(clip.bounds.origin.y - target) > 0.01 else { return }
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: target))
        scrollView.reflectScrolledClipView(clip)
    }

    /// Прижать ленту к низу, если она уже не там. Прямая установка offset
    /// дешевле `ScrollViewProxy.scrollTo` и не вызывает перестройку дерева
    /// вью на каждый чанк стриминга.
    func pinToBottom() {
        guard let scrollView = (self.scrollView?.window != nil ? self.scrollView : resolvedScrollView()) else {
            return
        }
        let snap = snapshot(for: scrollView)
        guard snap.maxOffsetY > 0 else { return }
        guard !ChatScrollMath.isAtBottom(offset: snap.offsetY, maxOffset: snap.maxOffsetY, slack: 2) else {
            return
        }
        let clip = scrollView.contentView
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: snap.maxOffsetY))
        scrollView.reflectScrolledClipView(clip)
    }

    // MARK: - Window fallback

    /// When no probe has attached (e.g. the lazy stack has not materialized
    /// the bottom sentinel yet), find the most likely chat scroll view by
    /// scanning the key window's view tree. The chat scroll view is the
    /// largest visible vertical scroll container. This keeps the API usable
    /// in every scroll position — the probe remains the preferred source.
    func windowScrollViews() -> [(view: NSScrollView, area: CGFloat, documentHeight: CGFloat, frame: CGRect)] {
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

    func resolvedScrollView() -> NSScrollView? {
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

    func recordSample() {
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
        onScroll?(current)
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
