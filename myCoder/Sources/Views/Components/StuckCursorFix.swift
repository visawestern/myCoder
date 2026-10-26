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

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { event in
            DispatchQueue.main.async {
                StuckCursorFix.restoreArrowIfStuck()
            }
            return event
        }
    }

    static func restoreArrowIfStuck() {
        guard NSCursor.current == NSCursor.iBeam else { return }
        if isOverTextEditingView() { return }
        if isOverActionView() {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    /// True when the deepest view under the pointer is a text surface that
    /// legitimately owns the I-beam: an editable/selectable NSTextView or an
    /// enabled NSTextField.
    static func isOverTextEditingView() -> Bool {
        guard let hit = hitViewUnderPointer() else { return false }
        var current: NSView? = hit
        while let view = current {
            if let textView = view as? NSTextView {
                return textView.isEditable || textView.isSelectable
            }
            if let field = view as? NSTextField {
                return field.isEnabled && field.isEditable
            }
            current = view.superview
        }
        return false
    }

    /// True when the pointer sits on an accessible button. SwiftUI renders
    /// plain buttons without an NSButton, but it does publish the button
    /// accessibility role — use that to show the pointing hand instead of the
    /// arrow after a text view leaves its I-beam behind.
    static func isOverActionView() -> Bool {
        guard let hit = hitViewUnderPointer() else { return false }
        var current: NSView? = hit
        while let view = current {
            let role = view.accessibilityRole()?.rawValue
            if CursorHitLogic.isAction(role: role, actionNames: []) { return true }
            current = view.superview
        }
        return false
    }

    private static func hitViewUnderPointer() -> NSView? {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }),
              let content = window.contentView else {
            return nil
        }
        let location = window.mouseLocationOutsideOfEventStream
        return content.hitTest(content.convert(location, from: nil))
    }
}
