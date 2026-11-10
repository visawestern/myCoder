import SwiftUI
import AppKit

/// Renders a markdown message into ONE selectable text surface.
///
/// The SwiftUI renderer draws every markdown block as its own `Text` view.
/// Each `Text` is a separate selection island, so a drag can never cross a
/// heading, a bullet and the next paragraph — in practice only one line could
/// be selected at a time. This view draws the whole message into a single
/// read-only `NSTextView`: the selection spans the entire answer, Copy yields
/// plain text, and the standard macOS text menu applies to the whole message.
struct SelectableMarkdownTextView: NSViewRepresentable {
    let text: String
    var fontSize: CGFloat = 14
    var textColor: Color = Color.mimo.textPrimary
    var projectRoot: String? = nil

    @Environment(\.interfaceFontScale) private var interfaceFontScale
    @Environment(\.codeDisplaySettings) private var codeSettings

    private var scaledFontSize: CGFloat {
        InterfaceTypography.scaled(fontSize, scale: interfaceFontScale)
    }

    func makeNSView(context: Context) -> NSTextView {
        let textView = PathClickTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.allowsUndo = false
        textView.usesFindBar = false
        textView.setContentHuggingPriority(.defaultLow, for: .vertical)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        textView.menuCoordinator = context.coordinator
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        guard let pathView = textView as? PathClickTextView else { return }
        pathView.menuCoordinator = context.coordinator
        MarkdownAttributedStringBuilder.noteNSViewUpdate()
        let attributed = MarkdownAttributedStringBuilder.cachedBuild(
            text: text,
            fontSize: scaledFontSize,
            textColor: textColor,
            projectRoot: projectRoot,
            codeSettings: codeSettings,
            isLightInterface: Color.mimo.isLightTheme
        )
        guard pathView.attributedString() != attributed else { return }

        // Keep the user's selection while the answer keeps streaming in.
        let selectedRange = pathView.selectedRange()
        pathView.textStorage?.setAttributedString(attributed)
        if selectedRange.length > 0,
           selectedRange.location + selectedRange.length <= attributed.length {
            pathView.setSelectedRange(selectedRange)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView textView: NSTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? textView.bounds.width
        guard width > 0 else { return nil }
        MarkdownAttributedStringBuilder.noteSizeThatFitsCall()
        let height = MarkdownAttributedStringBuilder.cachedMeasuredHeight(
            text: text,
            fontSize: scaledFontSize,
            textColor: textColor,
            projectRoot: projectRoot,
            codeSettings: codeSettings,
            isLightInterface: Color.mimo.isLightTheme,
            width: width
        ) {
            MarkdownAttributedStringBuilder.measuredHeight(for: textView, width: width)
        }
        return CGSize(width: width, height: height)
    }

    func makeCoordinator() -> FileOpenMenuCoordinator {
        FileOpenMenuCoordinator()
    }
}

final class PathClickTextView: NSTextView {
    weak var menuCoordinator: FileOpenMenuCoordinator?
    private var mouseDownLocation: NSPoint = .zero

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = convert(event.locationInWindow, from: nil)
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        guard event.clickCount == 1 else { return }
        let upLocation = convert(event.locationInWindow, from: nil)
        guard abs(upLocation.x - mouseDownLocation.x) < 4, abs(upLocation.y - mouseDownLocation.y) < 4 else { return }
        guard selectedRange().length == 0 else { return }
        guard let path = filePath(at: upLocation) else { return }
        menuCoordinator?.presentOpenWithMenu(for: path, at: event.locationInWindow)
    }

    private func filePath(at point: NSPoint) -> String? {
        guard let layoutManager, let container = textContainer else { return nil }
        let index = layoutManager.characterIndex(
            for: point,
            in: container,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        guard let storage = textStorage, storage.length > 0 else { return nil }
        let clamped = min(index, storage.length - 1)
        return storage.attribute(
            .chatFilePath,
            at: clamped,
            effectiveRange: nil
        ) as? String
    }
}

final class FileOpenMenuCoordinator: NSObject {
    func presentOpenWithMenu(for absolutePath: String, at screenPoint: NSPoint) {
        let fileURL = URL(fileURLWithPath: absolutePath)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: absolutePath, isDirectory: &isDirectory)

        if exists, isDirectory.boolValue {
            // Папка: открыть её в Finder (или в приложении по умолчанию).
            let menu = NSMenu()
            let openInFinder = NSMenuItem(
                title: L.t("Открыть в Finder"),
                action: #selector(openInFinder(_:)),
                keyEquivalent: ""
            )
            openInFinder.target = self
            openInFinder.representedObject = FileOpenTarget(fileURL: fileURL, applicationURL: nil)
            menu.addItem(openInFinder)
            let reveal = NSMenuItem(
                title: L.t("Reveal in Finder"),
                action: #selector(revealInFinder(_:)),
                keyEquivalent: ""
            )
            reveal.target = self
            reveal.representedObject = FileOpenTarget(fileURL: fileURL, applicationURL: nil)
            menu.addItem(reveal)
            menu.popUp(positioning: nil, at: screenPoint, in: nil)
            return
        }

        let defaultApp = ChatFileOpenLogic.defaultApplication(fileURL: fileURL)
        let others = ChatFileOpenLogic.applicationsThatCanOpen(fileURL: fileURL)
        let ordered = ChatFileOpenLogic.orderedApplications(default: defaultApp, candidates: others)

        let menu = NSMenu()
        let defaultItem = NSMenuItem(
            title: L.t("Open with") + " — " + (defaultApp.map { ChatFileOpenLogic.applicationName(at: $0) } ?? L.t("Default application")),
            action: #selector(openWithDefault(_:)),
            keyEquivalent: ""
        )
        defaultItem.target = self
        defaultItem.representedObject = FileOpenTarget(fileURL: fileURL, applicationURL: defaultApp)
        menu.addItem(defaultItem)

        for appURL in ordered.dropFirst().prefix(8) {
            let item = NSMenuItem(
                title: ChatFileOpenLogic.applicationName(at: appURL),
                action: #selector(openWithApp(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = FileOpenTarget(fileURL: fileURL, applicationURL: appURL)
            menu.addItem(item)
        }

        if !ordered.dropFirst().isEmpty {
            menu.addItem(.separator())
        }
        let finderItem = NSMenuItem(
            title: L.t("Reveal in Finder"),
            action: #selector(revealInFinder(_:)),
            keyEquivalent: ""
        )
        finderItem.target = self
        finderItem.representedObject = FileOpenTarget(fileURL: fileURL, applicationURL: nil)
        menu.addItem(finderItem)

        menu.popUp(positioning: nil, at: screenPoint, in: nil)
    }

    @objc private func openInFinder(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? FileOpenTarget else { return }
        ChatFileOpenLogic.open(fileURL: target.fileURL, applicationURL: nil)
    }

    @objc private func openWithDefault(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? FileOpenTarget else { return }
        ChatFileOpenLogic.open(fileURL: target.fileURL, applicationURL: target.applicationURL)
    }

    @objc private func openWithApp(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? FileOpenTarget else { return }
        ChatFileOpenLogic.open(fileURL: target.fileURL, applicationURL: target.applicationURL)
    }

    @objc private func revealInFinder(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? FileOpenTarget else { return }
        ChatFileOpenLogic.revealInFinder(fileURL: target.fileURL)
    }
}

final class FileOpenTarget: NSObject {
    let fileURL: URL
    let applicationURL: URL?

    init(fileURL: URL, applicationURL: URL?) {
        self.fileURL = fileURL
        self.applicationURL = applicationURL
    }
}

extension NSAttributedString.Key {
    static let chatFilePath = NSAttributedString.Key("com.mycoder.chatFilePath")
}

/// Builds the attributed string of a markdown message and measures its height.
/// Live counters for the markdown render and layout caches.
///
/// A scrolling stall has exactly two expensive candidates on the main thread:
/// parsing a message into an attributed string, and TextKit laying that string
/// out at the current width. Guessing between them is not acceptable, so the
/// counters are exposed through `GET /api/markdown-perf` and verified with a
/// real scroll pass.
struct MarkdownRenderStats: Equatable {
    var cacheHits = 0
    var cacheMisses = 0
    var buildCount = 0
    var buildTotalMilliseconds = 0.0
    var buildMaxMilliseconds = 0.0
    var prewarmRuns = 0
    var prewarmBuilt = 0
    var heightHits = 0
    var heightMisses = 0
    var heightTotalMilliseconds = 0.0
    var heightMaxMilliseconds = 0.0
    var cacheEntries = 0
    var cacheCharacters = 0
    var heightEntries = 0
    var nsViewUpdates = 0
    var sizeThatFitsCalls = 0

    var dictionary: [String: Any] {
        [
            "cacheHits": cacheHits,
            "cacheMisses": cacheMisses,
            "buildCount": buildCount,
            "buildTotalMs": (buildTotalMilliseconds * 1000).rounded() / 1000,
            "buildMaxMs": (buildMaxMilliseconds * 1000).rounded() / 1000,
            "prewarmRuns": prewarmRuns,
            "prewarmBuilt": prewarmBuilt,
            "heightHits": heightHits,
            "heightMisses": heightMisses,
            "heightTotalMs": (heightTotalMilliseconds * 1000).rounded() / 1000,
            "heightMaxMs": (heightMaxMilliseconds * 1000).rounded() / 1000,
            "cacheEntries": cacheEntries,
            "cacheCharacters": cacheCharacters,
            "heightEntries": heightEntries,
            "nsViewUpdates": nsViewUpdates,
            "sizeThatFitsCalls": sizeThatFitsCalls
        ]
    }
}

enum MarkdownAttributedStringBuilder {
    // MARK: - Render cache
    //
    // Building the attributed string is expensive (parser + regex + syntax
    // highlighting), and TextKit laying it out at a width is expensive again.
    // Both used to run on the main thread every time a lazy row materialized,
    // which is what made scrolling "stall" at the boundary of a big message.
    //
    // Two caches now sit in front of that work:
    //   * attributed strings, keyed by everything that changes the output;
    //   * measured heights, keyed by the same profile plus the layout width.
    //
    // Both are written from the main thread (row updates) and from a utility
    // task (prewarm), so every access is guarded by `cacheLock`. Eviction is
    // FIFO with a character budget: large chats cannot grow the cache without
    // bound, and an entry larger than the whole budget is still kept because
    // it is exactly the message the user is scrolling through.

    /// Snapshot every prose color from the explicit render profile. Reading
    /// mutable Color.mimo tokens here let an off-main prewarm mix themes and
    /// store that result under a key which only described isLightInterface.
    struct InterfacePalette {
        let muted: NSColor
        let border: NSColor
        let brand: NSColor
        let thinking: NSColor

        init(isLight: Bool) {
            // Exact Sci-Fi Light/Dark values from MiMoColors. That API exposes
            // only global theme-dependent getters, so it cannot be queried by
            // a renderer whose explicit profile may differ from global state.
            muted = NSColor(isLight
                ? Color(red: 0.28, green: 0.38, blue: 0.52)
                : Color(red: 0.431, green: 0.463, blue: 0.506))
            border = NSColor(isLight
                ? Color(red: 0.62, green: 0.74, blue: 0.88)
                : Color(red: 0.188, green: 0.212, blue: 0.239))
            // These design tokens are immutable and shared by both themes.
            brand = NSColor(Color.mimo.brand)
            thinking = NSColor(Color.mimo.thinking)
        }
    }

    struct RenderKey: Hashable {
        let text: String
        let fontSize: CGFloat
        let textColorRGBA: UInt32
        let isLight: Bool
        let lightTheme: String
        let darkTheme: String
        let codeFontSize: Int
        let showLineNumbers: Bool
        let wrapLongLines: Bool
        let projectRoot: String?
    }

    struct HeightKey: Hashable {
        let render: RenderKey
        let width: CGFloat
    }

    static let cacheLock = NSLock()
    static var cache: [RenderKey: NSAttributedString] = [:]
    static var cacheOrder: [RenderKey] = []
    static var cacheCharacters = 0
    static let maxCacheEntries = 120
    static let maxCacheCharacters = 16_000_000

    static var heightCache: [HeightKey: CGFloat] = [:]
    static var heightOrder: [HeightKey] = []
    static let maxHeightEntries = 300

    static var stats = MarkdownRenderStats()

    static func rgba(_ color: Color) -> UInt32 {
        let ns = NSColor(color).usingColorSpace(.sRGB)
        let r = UInt32(max(0, min(1, ns?.redComponent ?? 0)) * 255)
        let g = UInt32(max(0, min(1, ns?.greenComponent ?? 0)) * 255)
        let b = UInt32(max(0, min(1, ns?.blueComponent ?? 0)) * 255)
        let a = UInt32(max(0, min(1, ns?.alphaComponent ?? 1)) * 255)
        return (r << 24) | (g << 16) | (b << 8) | a
    }

    static func key(
        text: String,
        fontSize: CGFloat,
        textColor: Color,
        projectRoot: String?,
        codeSettings: CodeDisplaySettings,
        isLightInterface: Bool
    ) -> RenderKey {
        RenderKey(
            text: text,
            fontSize: fontSize,
            textColorRGBA: rgba(textColor),
            isLight: isLightInterface,
            lightTheme: codeSettings.lightThemeName,
            darkTheme: codeSettings.darkThemeName,
            codeFontSize: codeSettings.fontSize,
            showLineNumbers: codeSettings.showLineNumbers,
            wrapLongLines: codeSettings.wrapLongLines,
            projectRoot: projectRoot
        )
    }

    static func evictIfNeededLocked() {
        while (cache.count > maxCacheEntries || cacheCharacters > maxCacheCharacters),
              cacheOrder.count > 1 {
            let victim = cacheOrder.removeFirst()
            if let removed = cache.removeValue(forKey: victim) {
                cacheCharacters -= removed.length
            }
        }
    }

    /// Build from cache when possible. Identical output to `build`.
}
