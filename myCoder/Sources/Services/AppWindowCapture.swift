import AppKit
import Foundation

/// Screenshot of the app's own window, captured from inside the process.
///
/// This is the AppKit analogue of a browser's `captureVisibleTab()`: no Screen
/// Recording permission for the window server, no `screencapture` subprocess,
/// just the window's own view tree rendered into a bitmap. Three strategies are
/// tried in order because layer-backed SwiftUI content behaves differently
/// from plain AppKit views:
///
/// 1. `cacheDisplay(in:to:)` — exact for AppKit controls and text.
/// 2. `CALayer.render(in:)` — covers SwiftUI's layer tree.
/// 3. `dataWithPDF(inside:)` — last resort for views that only draw in PDF.
///
/// The chosen strategy is reported so a blank screenshot is never passed off as
/// success without a trace.
@MainActor
enum AppWindowCapture {
    struct Shot {
        let pngData: Data
        let width: Int
        let height: Int
        let method: String
        let windowTitle: String
        let pointSize: CGSize
    }

    static func frontWindow() -> NSWindow? {
        NSApp.keyWindow
            ?? NSApp.mainWindow
            ?? NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil })
    }

    static func capture(window: NSWindow? = nil) -> Shot? {
        guard let window = window ?? frontWindow(),
              let view = window.contentView,
              view.bounds.width > 1,
              view.bounds.height > 1 else {
            return nil
        }

        if let rep = cacheDisplay(view: view),
           let shot = png(from: rep, method: "cacheDisplay", window: window) {
            return shot
        }
        if let rep = layerRender(view: view, scale: window.backingScaleFactor),
           let shot = png(from: rep, method: "layerRender", window: window) {
            return shot
        }
        if let rep = pdfRender(view: view),
           let shot = png(from: rep, method: "pdf", window: window) {
            return shot
        }
        return nil
    }

    static func write(_ shot: Shot, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try shot.pngData.write(to: url, options: .atomic)
    }

    static func defaultURL() -> URL {
        let stamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("mycoder-window-\(stamp).png")
    }

    // MARK: - Renderers

    private static func cacheDisplay(view: NSView) -> NSBitmapImageRep? {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return nil
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard !isBlank(rep) else { return nil }
        return rep
    }

    private static func layerRender(view: NSView, scale: CGFloat) -> NSBitmapImageRep? {
        guard let layer = view.layer else { return nil }
        let factor = max(1, scale)
        let width = Int((view.bounds.width * factor).rounded(.up))
        let height = Int((view.bounds.height * factor).rounded(.up))
        guard width > 1, height > 1,
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        // AppKit's coordinate system is bottom-left; the bitmap must be
        // top-left, so flip vertically before rendering the layer tree.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: factor, y: -factor)
        layer.render(in: context)

        guard let image = context.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = view.bounds.size
        guard !isBlank(rep) else { return nil }
        return rep
    }

    private static func pdfRender(view: NSView) -> NSBitmapImageRep? {
        let data = view.dataWithPDF(inside: view.bounds)
        guard !data.isEmpty,
              let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        guard !isBlank(rep) else { return nil }
        return rep
    }

    private static func png(
        from rep: NSBitmapImageRep,
        method: String,
        window: NSWindow
    ) -> Shot? {
        guard let data = rep.representation(using: .png, properties: [:]) else {
            return nil
        }
        return Shot(
            pngData: data,
            width: rep.pixelsWide,
            height: rep.pixelsHigh,
            method: method,
            windowTitle: window.title,
            pointSize: rep.size
        )
    }

    /// A single flat colour (or full transparency) means the strategy rendered
    /// nothing — report that as a failure so the caller can try the next one.
    private static func isBlank(_ rep: NSBitmapImageRep) -> Bool {
        guard rep.pixelsWide > 0, rep.pixelsHigh > 0 else { return true }
        let stepX = max(1, rep.pixelsWide / 24)
        let stepY = max(1, rep.pixelsHigh / 24)
        var colors: Set<UInt32> = []
        var visible = 0
        var y = 0
        while y < rep.pixelsHigh {
            var x = 0
            while x < rep.pixelsWide {
                if let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) {
                    let alpha = UInt32((color.alphaComponent * 255).rounded())
                    if alpha > 8 {
                        visible += 1
                        let rgba = (UInt32((color.redComponent * 255).rounded()) << 24)
                            | (UInt32((color.greenComponent * 255).rounded()) << 16)
                            | (UInt32((color.blueComponent * 255).rounded()) << 8)
                            | alpha
                        colors.insert(rgba)
                    }
                }
                x += stepX
            }
            y += stepY
        }
        if visible == 0 { return true }
        return colors.count <= 1
    }
}
