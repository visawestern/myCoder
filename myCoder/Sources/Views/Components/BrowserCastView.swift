import SwiftUI
import AppKit

/// Мини-каст вкладки браузера: показывает живой кадр из `ScreencastController`
/// и передаёт пользовательский ввод (клик/скролл) в браузер через REST
/// `/act/*` моста. Координаты пересчитываются из размера вью в viewport.
struct BrowserCastView: NSViewRepresentable {
    let screencast: ScreencastController
    let bridge: AntiBrowserAutomationBridge

    func makeNSView(context: Context) -> CastNSView {
        let view = CastNSView()
        // Ввод строго последовательный: каждый символ — отдельный REST-запрос,
        // и параллельные задачи могли бы переставить буквы местами.
        let inputQueue = SerialInputQueue()
        view.onClick = { point in
            inputQueue.run { try? await bridge.clickAt(x: point.x, y: point.y) }
        }
        view.onScroll = { dx, dy in
            Task { try? await bridge.scrollBy(dx: dx, dy: dy) }
        }
        // Ввод с клавиатуры: печать идёт в сфокусированное поле страницы,
        // спецклавиши — отдельными нажатиями. Без этого вход в аккаунт
        // через каст был невозможен (поддерживалась только мышь).
        view.onType = { text in
            inputQueue.run { try? await bridge.typeTextGlobal(text) }
        }
        view.onKey = { key in
            inputQueue.run { try? await bridge.pressKey(key) }
        }
        return view
    }

    func updateNSView(_ nsView: CastNSView, context: Context) {
        nsView.frameImage = screencast.frame
        nsView.viewportSize = screencast.viewportSize
        nsView.needsDisplay = true
    }
}

/// Последовательная очередь ввода каста: гарантирует порядок символов и
/// нажатий, чтобы быстрая печать не перемешивалась между REST-запросами.
@MainActor
final class SerialInputQueue {
    private var tail: Task<Void, Never>?

    func run(_ operation: @escaping @MainActor () async -> Void) {
        let previous = tail
        tail = Task { @MainActor in
            await previous?.value
            await operation()
        }
    }
}

/// NSView, рисующий последний кадр каста и ловящий мышь/колесо.
final class CastNSView: NSView {    var frameImage: CGImage?
    /// CSS-размер страницы (то, в чём /act/* принимает координаты).
    var viewportSize: CGSize?
    var onClick: ((CGPoint) -> Void)?
    var onScroll: ((CGFloat, CGFloat) -> Void)?
    var onType: ((String) -> Void)?
    var onKey: ((String) -> Void)?

    /// Flipped: Y растёт вниз, как в viewport браузера.
    override var isFlipped: Bool { true }

    /// Каст принимает клавиатуру, чтобы печатать в поля страницы.
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let image = frameImage else { return }
        let rect = contentRect(for: bounds.size, image: image)
        let context = NSGraphicsContext.current?.cgContext
        context?.interpolationQuality = .high
        context?.draw(image, in: rect)
    }

    /// Прямоугольник картинки при aspect-fit.
    private func contentRect(for size: CGSize, image: CGImage) -> CGRect {
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        let scale = min(size.width / imageWidth, size.height / imageHeight)
        let width = imageWidth * scale
        let height = imageHeight * scale
        return CGRect(x: (size.width - width) / 2,
                      y: (size.height - height) / 2,
                      width: width,
                      height: height)
    }

    /// Пересчёт точки вью → точка viewport браузера (CSS-пиксели).
    /// Позиция нормализуется по нарисованному кадру и умножается на CSS-размер:
    /// скриншот на Retina в 2× больше CSS-viewport, и без этого клики уходили
    /// мимо элементов (вдвое дальше к правому нижнему углу).
    private func viewportPoint(from point: CGPoint) -> CGPoint? {
        guard let image = frameImage else { return nil }
        let rect = contentRect(for: bounds.size, image: image)
        guard rect.contains(point) else { return nil }
        let nx = (point.x - rect.minX) / rect.width
        let ny = (point.y - rect.minY) / rect.height
        let css = viewportSize ?? CGSize(width: CGFloat(image.width),
                                         height: CGFloat(image.height))
        return CGPoint(x: nx * css.width, y: ny * css.height)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        if let viewport = viewportPoint(from: point) {
            onClick?(viewport)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        onScroll?(event.scrollingDeltaX, event.scrollingDeltaY)
    }

    override func keyDown(with event: NSEvent) {
        // Cmd+V — вставка из буфера (пароли часто вставляют, а не печатают).
        if event.modifierFlags.contains(.command) {
            if event.charactersIgnoringModifiers?.lowercased() == "v" {
                if let text = NSPasteboard.general.string(forType: .string),
                   !text.isEmpty {
                    onType?(text)
                }
                return
            }
            super.keyDown(with: event)
            return
        }
        // Спецклавиши отправляем именем, остальное — как текст.
        if let key = Self.keyName(for: event.keyCode) {
            onKey?(key)
            return
        }
        if let text = event.characters, !text.isEmpty,
           !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            onType?(text)
            return
        }
        super.keyDown(with: event)
    }

    /// Имена клавиш, которые понимает `/act/key` движка.
    private static func keyName(for keyCode: UInt16) -> String? {
        switch keyCode {
        case 36, 76: return "Enter"
        case 48: return "Tab"
        case 53: return "Escape"
        case 51: return "Backspace"
        case 117: return "Delete"
        case 123: return "Left"
        case 124: return "Right"
        case 125: return "Down"
        case 126: return "Up"
        case 115: return "Home"
        case 119: return "End"
        case 116: return "PageUp"
        case 121: return "PageDown"
        case 49: return "Space"
        default: return nil
        }
    }
}

/// Владелец скринкаста для панели чата: создаёт контроллер под мост
/// вкладки и включает/выключает трансляцию вместе с жизнью панели.
struct CastPanelHost: View {
    let bridge: AntiBrowserAutomationBridge

    @StateObject private var screencast: ScreencastController

    init(bridge: AntiBrowserAutomationBridge) {
        self.bridge = bridge
        _screencast = StateObject(wrappedValue: ScreencastController(bridge: bridge))
    }

    var body: some View {
        BrowserCastView(screencast: screencast, bridge: bridge)
            .onAppear { screencast.start() }
            .onDisappear { screencast.stop() }
    }
}

/// Renders the app-wide always-on cast instead of creating a second
/// screenshot loop. The chat panel and the right-sidebar CHROMECAST PiP share
/// this controller, so one tab is polled exactly once. If the store has not
/// reached this tab yet, `.task` activates it on the next runloop.
struct SharedCastPanelHost: View {
    @ObservedObject var store: WebBrowserCastStore
    let config: WebBrowserPanelConfig

    var body: some View {
        Group {
            if store.config == config,
               let screencast = store.controller,
               let bridge = store.bridge {
                BrowserCastView(screencast: screencast, bridge: bridge)
            } else {
                Color.mimo.background
            }
        }
        .task(id: config) {
            store.activate(config)
        }
    }
}
