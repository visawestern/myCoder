import AppKit
import SwiftUI

/// Kills the stuck text-insertion cursor. On macOS a visited NSTextView (chat
/// bubble, editable field) leaves the I-beam cursor active far beyond its own
/// bounds — buttons, row titles and sidebar items then show the text cursor
/// as if they were text. A local mouse-move monitor watches the cursor: when
/// it is the I-beam and the view under the pointer is not a text-editing
/// view, the arrow is restored. Hand-cursor hovers (buttons, rows) are never
/// touched — they set their own cursor explicitly.
enum StuckCursorFix {
    private static var monitor: Any?
    /// Number of times the local event monitor has fired since launch. A
    /// diagnostic (GET /api/debug/cursor) to verify hover events actually
    /// reach the app (default NSWindow does NOT accept .mouseMoved events).
    private(set) static var monitoredEventCount = 0

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { event in
            monitoredEventCount += 1
            // Capture the coordinates at event time; the async hop below must
            // not read `mouseLocationOutsideOfEventStream` (can be stale when
            // the window is not key).
            let location = event.locationInWindow
            DispatchQueue.main.async {
                StuckCursorFix.restoreArrowIfStuck(at: location)
            }
            return event
        }
    }

    static func restoreArrowIfStuck(at location: NSPoint? = nil) {
        // Text-editing surfaces (an editable/selectable NSTextView or an
        // enabled NSTextField) own the I-beam natively (zeroInsetTextView
        // cursor rects + cursorUpdate). Never fight them: just make sure the
        // I-beam is current and stop.
        if textEditingViewUnderPointer(at: location) != nil {
            if NSCursor.current != NSCursor.iBeam {
                NSCursor.iBeam.set()
            }
            return
        }
        guard NSCursor.current == NSCursor.iBeam else { return }
        if isOverActionView(at: location) {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    /// True when the deepest view under the pointer is a text surface that
    /// legitimately owns the I-beam: an editable/selectable NSTextView or an
    /// enabled NSTextField.
    static func isOverTextEditingView(at location: NSPoint? = nil) -> Bool {
        textEditingViewUnderPointer(at: location) != nil
    }

    /// The deepest text-editing surface under the pointer (window-local
    /// coordinates, e.g. `event.locationInWindow`).
    static func textEditingViewUnderPointer(at location: NSPoint?) -> NSView? {
        guard let hit = hitViewUnderPointer(at: location) else { return nil }
        return textEditingView(hit: hit)
    }

    private static func textEditingView(hit: NSView?) -> NSView? {
        var current: NSView? = hit
        while let view = current {
            if let textView = view as? NSTextView, textView.isEditable || textView.isSelectable {
                return view
            }
            if let field = view as? NSTextField, field.isEnabled && field.isEditable {
                return view
            }
            current = view.superview
        }
        return nil
    }

    /// True when the pointer sits on an accessible button. SwiftUI renders
    /// plain buttons without an NSButton, but it does publish the button
    /// accessibility role — use that to show the pointing hand instead of the
    /// arrow after a text view leaves its I-beam behind.
    static func isOverActionView(at location: NSPoint? = nil) -> Bool {
        guard let hit = hitViewUnderPointer(at: location) else { return false }
        var current: NSView? = hit
        while let view = current {
            let role = view.accessibilityRole()?.rawValue
            if CursorHitLogic.isAction(role: role, actionNames: []) { return true }
            current = view.superview
        }
        return false
    }

    private static func hitViewUnderPointer(at location: NSPoint?) -> NSView? {
        guard let window = topWindowUnderPointer(),
              let content = window.contentView else {
            return nil
        }
        let local: NSPoint
        if let location {
            // Window-local coordinates (e.g. event.locationInWindow).
            local = location
        } else {
            local = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        }
        return content.hitTest(local)
    }

    private static func topWindowUnderPointer() -> NSWindow? {
        NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible })
    }
}

/// Read-only diagnostics for cursor verification (endpoint `GET /api/debug/cursor`).
/// Reports the exact current cursor identity, the mouse position, and — for the
/// window that contains the mouse — the view chain under the pointer with text-ness
/// flags. Lets an external driver (cliclick + curl) verify real cursor behavior in
/// the running app instead of guessing from screenshots.
enum CursorDiagnostics {
    static func snapshot() -> [String: Any] {
        let mouse = NSEvent.mouseLocation
        let mainScreenHeight = NSScreen.main?.frame.height ?? 0

        var cursorName = "unknown"
        let cursor = NSCursor.current
        if cursor === NSCursor.iBeam { cursorName = "iBeam" }
        else if cursor === NSCursor.arrow { cursorName = "arrow" }
        else if cursor === NSCursor.pointingHand { cursorName = "pointingHand" }
        else if cursor === NSCursor.crosshair { cursorName = "crosshair" }
        else { cursorName = String(describing: cursor) }

        var windows: [[String: Any]] = []
        var targetWindow: [String: Any] = [:]
        for window in NSApp.windows where window.isVisible {
            let local = window.convertPoint(fromScreen: mouse)
            var entry: [String: Any] = [
                "title": window.title,
                "frame": [
                    "x": window.frame.origin.x,
                    "y": window.frame.origin.y,
                    "width": window.frame.width,
                    "height": window.frame.height
                ],
                "containsMouse": window.frame.contains(mouse),
                "localPoint": ["x": local.x, "y": local.y]
            ]
            if let content = window.contentView {
                entry["textViews"] = textViews(in: content, window: window)
            }
            if window.frame.contains(mouse), let content = window.contentView {
                let hit = content.hitTest(local)
                var chain: [[String: Any]] = []
                var textUnderPointer = false
                var current: NSView? = hit
                while let view = current {
                    var info: [String: Any] = ["class": String(describing: type(of: view))]
                    if let textView = view as? NSTextView {
                        info["isEditable"] = textView.isEditable
                        info["isSelectable"] = textView.isSelectable
                        info["isFieldEditor"] = textView.isFieldEditor
                        if textView.isEditable || textView.isSelectable { textUnderPointer = true }
                    }
                    if let field = view as? NSTextField {
                        info["isEnabled"] = field.isEnabled
                        info["isEditable"] = field.isEditable
                        if field.isEnabled && field.isEditable { textUnderPointer = true }
                    }
                    chain.append(info)
                    current = view.superview
                }
                entry["hitChain"] = chain
                entry["textUnderPointer"] = textUnderPointer
                targetWindow = entry
            }
            windows.append(entry)
        }

        return [
            "cursor": cursorName,
            "monitorFires": StuckCursorFix.monitoredEventCount,
            "cursorUpdateFired": ZeroInsetTextView.cursorUpdateFired,
            "mouseScreenBottomLeft": ["x": mouse.x, "y": mouse.y],
            "mainScreenHeight": mainScreenHeight,
            "windows": windows,
            "targetWindow": targetWindow
        ]
    }

    /// Recursively collect every text-editing surface (NSTextView subclass /
    /// NSTextField) in the hierarchy with its frame in window coordinates.
    private static func textViews(in view: NSView, window: NSWindow) -> [[String: Any]] {
        var result: [[String: Any]] = []
        if let textView = view as? NSTextView {
            let frameInWindow = view.convert(view.bounds, to: nil)
            result.append([
                "class": String(describing: type(of: view)),
                "frameInWindow": ["x": frameInWindow.origin.x, "y": frameInWindow.origin.y,
                                  "width": frameInWindow.width, "height": frameInWindow.height],
                "isEditable": textView.isEditable,
                "isSelectable": textView.isSelectable
            ])
        } else if let field = view as? NSTextField {
            let frameInWindow = view.convert(view.bounds, to: nil)
            result.append([
                "class": "NSTextField",
                "frameInWindow": ["x": frameInWindow.origin.x, "y": frameInWindow.origin.y,
                                  "width": frameInWindow.width, "height": frameInWindow.height],
                "isEditable": field.isEditable,
                "isEnabled": field.isEnabled
            ])
        }
        for subview in view.subviews {
            result.append(contentsOf: textViews(in: subview, window: window))
        }
        return result
    }
}
