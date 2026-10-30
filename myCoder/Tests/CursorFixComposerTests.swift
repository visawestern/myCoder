import XCTest
import AppKit
import SwiftUI
@testable import myCoder

/// Глобальный монитор `StuckCursorFix` сбрасывает I-beam в стрелку, только
/// если под указателем НЕ текстовая редактируемая поверхность. Эти тесты
/// фиксируют, что поле ввода сообщения (ZeroInsetTextView) распознаётся как
/// текстовая поверхность (регрессия: стрелочка при наведении на композер,
/// репорт 2026-10-30).
@MainActor
final class CursorFixComposerTests: XCTestCase {

    private func makeWindow() -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        return window
    }

    private func makeComposerTextView(in window: NSWindow) -> (ZeroInsetTextView, NSPoint) {
        let textView = ZeroInsetTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        textView.isEditable = true
        textView.isSelectable = true
        window.contentView = textView
        window.orderFront(nil)
        window.displayIfNeeded()
        // Точка в окне — по центру текстовой поверхности.
        let point = NSPoint(x: 200, y: 50)
        return (textView, point)
    }

    func testComposerIsTextEditingAndPlainBackgroundIsNot() {
        let window = makeWindow()
        defer { window.close() }

        // 1) Поле ввода: hitTest даёт text view → текстовая поверхность.
        let textView = ZeroInsetTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        textView.isEditable = true
        textView.isSelectable = true
        window.contentView = textView
        window.orderFront(nil)
        window.displayIfNeeded()

        let center = NSPoint(x: 200, y: 50)
        XCTAssertNotNil(window.contentView?.hitTest(center))
        XCTAssertTrue(
            StuckCursorFix.isOverTextEditingView(at: center),
            "поле ввода сообщения должно распознаваться как текстовая поверхность"
        )
        XCTAssertTrue(textView.isEditable)
        XCTAssertTrue(textView.isSelectable)

        // 2) Пустой фон: не текстовая поверхность.
        let background = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        window.contentView = background
        window.displayIfNeeded()
        XCTAssertFalse(
            StuckCursorFix.isOverTextEditingView(at: center),
            "пустой фон не должен считаться текстовой поверхностью"
        )
    }
}
