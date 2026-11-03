import SwiftUI
import AppKit

/// Транслирует содержимое вкладки браузера в кадры для мини-каста.
/// Снимки снимаются через CDP (Page.captureScreenshot) у того же моста,
/// который обслуживает чат — то есть каст всегда показывает именно ту
/// вкладку, в которой идёт разговор.
@MainActor
final class ScreencastController: ObservableObject {

    @Published private(set) var frame: CGImage?
    /// CSS-размер viewport для кадра. Картинка в физических пикселях (Retina),
    /// а ввод принимается в CSS-пикселях — без этого размеры расходятся.
    @Published private(set) var viewportSize: CGSize?
    @Published private(set) var isActive = false

    private let bridge: AntiBrowserAutomationBridge
    private var task: Task<Void, Never>?
    private let frameIntervalNanoseconds: UInt64 = 300_000_000 // ~3 FPS

    init(bridge: AntiBrowserAutomationBridge) {
        self.bridge = bridge
    }

    func start() {
        guard task == nil else { return }
        isActive = true
        task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                if let shot = try? await self.bridge.screenshotFrame(),
                   let image = NSImage(data: shot.data)?.cgImage(forProposedRect: nil,
                                                                context: nil,
                                                                hints: nil) {
                    self.frame = image
                    self.viewportSize = shot.cssSize
                }
                try? await Task.sleep(nanoseconds: frameIntervalNanoseconds)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isActive = false
    }

    deinit {
        task?.cancel()
    }
}
