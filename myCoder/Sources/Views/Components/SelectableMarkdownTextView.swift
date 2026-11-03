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
    private struct InterfacePalette {
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

    private struct RenderKey: Hashable {
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

    private struct HeightKey: Hashable {
        let render: RenderKey
        let width: CGFloat
    }

    private static let cacheLock = NSLock()
    private static var cache: [RenderKey: NSAttributedString] = [:]
    private static var cacheOrder: [RenderKey] = []
    private static var cacheCharacters = 0
    private static let maxCacheEntries = 120
    private static let maxCacheCharacters = 16_000_000

    private static var heightCache: [HeightKey: CGFloat] = [:]
    private static var heightOrder: [HeightKey] = []
    private static let maxHeightEntries = 300

    private static var stats = MarkdownRenderStats()

    private static func rgba(_ color: Color) -> UInt32 {
        let ns = NSColor(color).usingColorSpace(.sRGB)
        let r = UInt32(max(0, min(1, ns?.redComponent ?? 0)) * 255)
        let g = UInt32(max(0, min(1, ns?.greenComponent ?? 0)) * 255)
        let b = UInt32(max(0, min(1, ns?.blueComponent ?? 0)) * 255)
        let a = UInt32(max(0, min(1, ns?.alphaComponent ?? 1)) * 255)
        return (r << 24) | (g << 16) | (b << 8) | a
    }

    private static func key(
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

    private static func evictIfNeededLocked() {
        while (cache.count > maxCacheEntries || cacheCharacters > maxCacheCharacters),
              cacheOrder.count > 1 {
            let victim = cacheOrder.removeFirst()
            if let removed = cache.removeValue(forKey: victim) {
                cacheCharacters -= removed.length
            }
        }
    }

    /// Build from cache when possible. Identical output to `build`.
    static func cachedBuild(
        text: String,
        fontSize: CGFloat,
        textColor: Color,
        projectRoot: String? = nil,
        codeSettings: CodeDisplaySettings = .default,
        isLightInterface: Bool = Color.mimo.isLightTheme
    ) -> NSAttributedString {
        cachedBuildWithStatus(
            text: text,
            fontSize: fontSize,
            textColor: textColor,
            projectRoot: projectRoot,
            codeSettings: codeSettings,
            isLightInterface: isLightInterface
        ).attributed
    }

    private static func cachedBuildWithStatus(
        text: String,
        fontSize: CGFloat,
        textColor: Color,
        projectRoot: String?,
        codeSettings: CodeDisplaySettings,
        isLightInterface: Bool
    ) -> (attributed: NSAttributedString, wasHit: Bool) {
        let renderKey = key(
            text: text,
            fontSize: fontSize,
            textColor: textColor,
            projectRoot: projectRoot,
            codeSettings: codeSettings,
            isLightInterface: isLightInterface
        )

        cacheLock.lock()
        if let cached = cache[renderKey] {
            stats.cacheHits += 1
            cacheLock.unlock()
            return (cached, true)
        }
        stats.cacheMisses += 1
        cacheLock.unlock()

        let started = DispatchTime.now().uptimeNanoseconds
        let built = build(
            text: text,
            fontSize: fontSize,
            textColor: textColor,
            projectRoot: projectRoot,
            codeSettings: codeSettings,
            isLightInterface: isLightInterface
        )
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000

        cacheLock.lock()
        stats.buildCount += 1
        stats.buildTotalMilliseconds += elapsedMs
        stats.buildMaxMilliseconds = max(stats.buildMaxMilliseconds, elapsedMs)
        if cache[renderKey] == nil {
            cache[renderKey] = built
            cacheOrder.append(renderKey)
            cacheCharacters += built.length
            evictIfNeededLocked()
        }
        cacheLock.unlock()
        return (built, false)
    }

    /// Pre-render the prose segments of large messages right after history
    /// loads, so the first time their row appears the attributed string is
    /// already built. `texts` must be exactly the strings handed to
    /// `SelectableMarkdownTextView` (prose only, code fences excluded) and
    /// `fontSize`/`textColor` must match that renderer, otherwise every entry
    /// misses the cache and the work is wasted.
    ///
    /// Returns the number of entries actually built (cache misses).
    @discardableResult
    static func prewarm(
        texts: [String],
        fontSize: CGFloat,
        textColor: Color,
        projectRoot: String?,
        codeSettings: CodeDisplaySettings = .default,
        isLightInterface: Bool,
        threshold: Int = 800
    ) -> Int {
        guard !texts.isEmpty else { return 0 }
        var built = 0
        for text in texts where text.count >= threshold {
            if Task.isCancelled { break }
            let result = cachedBuildWithStatus(
                text: text,
                fontSize: fontSize,
                textColor: textColor,
                projectRoot: projectRoot,
                codeSettings: codeSettings,
                isLightInterface: isLightInterface
            )
            if !result.wasHit { built += 1 }
        }
        cacheLock.lock()
        stats.prewarmRuns += 1
        stats.prewarmBuilt += built
        cacheLock.unlock()
        return built
    }

    /// Height of the laid-out text at `width`, cached by the full render
    /// profile. Re-measuring the same message on every SwiftUI pass was the
    /// other half of the scroll stall.
    static func cachedMeasuredHeight(
        text: String,
        fontSize: CGFloat,
        textColor: Color,
        projectRoot: String?,
        codeSettings: CodeDisplaySettings,
        isLightInterface: Bool,
        width: CGFloat,
        measure: () -> CGFloat
    ) -> CGFloat {
        guard width > 0 else { return 1 }
        // Exact width is part of the key. Rounding looked tempting but a
        // sub-point change can move a line break, and a stale height would
        // clip the message; a repeated identical proposal still hits.
        let heightKey = HeightKey(
            render: key(
                text: text,
                fontSize: fontSize,
                textColor: textColor,
                projectRoot: projectRoot,
                codeSettings: codeSettings,
                isLightInterface: isLightInterface
            ),
            width: width
        )

        cacheLock.lock()
        if let cached = heightCache[heightKey] {
            stats.heightHits += 1
            cacheLock.unlock()
            return cached
        }
        stats.heightMisses += 1
        cacheLock.unlock()

        let started = DispatchTime.now().uptimeNanoseconds
        let height = measure()
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000

        cacheLock.lock()
        stats.heightTotalMilliseconds += elapsedMs
        stats.heightMaxMilliseconds = max(stats.heightMaxMilliseconds, elapsedMs)
        if heightCache[heightKey] == nil {
            heightCache[heightKey] = height
            heightOrder.append(heightKey)
            while heightCache.count > maxHeightEntries, heightOrder.count > 1 {
                let victim = heightOrder.removeFirst()
                heightCache.removeValue(forKey: victim)
            }
        }
        cacheLock.unlock()
        return height
    }

    /// Snapshot of the live counters (thread-safe).
    static func statsSnapshot() -> MarkdownRenderStats {
        cacheLock.lock()
        var copy = stats
        copy.cacheEntries = cache.count
        copy.cacheCharacters = cacheCharacters
        copy.heightEntries = heightCache.count
        cacheLock.unlock()
        return copy
    }

    /// Whether an attributed string for this exact render profile is already
    /// cached. Used by tests to prove that prewarming seeded the same entries
    /// the renderer asks for.
    static func cachedAttributedString(
        text: String,
        fontSize: CGFloat,
        textColor: Color,
        projectRoot: String?,
        codeSettings: CodeDisplaySettings,
        isLightInterface: Bool
    ) -> NSAttributedString? {
        let renderKey = key(
            text: text,
            fontSize: fontSize,
            textColor: textColor,
            projectRoot: projectRoot,
            codeSettings: codeSettings,
            isLightInterface: isLightInterface
        )
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cache[renderKey]
    }

    static func resetStats() {
        cacheLock.lock()
        stats = MarkdownRenderStats()
        cacheLock.unlock()
    }

    static func noteNSViewUpdate() {
        cacheLock.lock()
        stats.nsViewUpdates += 1
        cacheLock.unlock()
    }

    static func noteSizeThatFitsCall() {
        cacheLock.lock()
        stats.sizeThatFitsCalls += 1
        cacheLock.unlock()
    }

    /// Drop every cached render and height. Used by tests; also safe to call
    /// on memory pressure.
    static func clearCaches() {
        cacheLock.lock()
        cache.removeAll()
        cacheOrder.removeAll()
        cacheCharacters = 0
        heightCache.removeAll()
        heightOrder.removeAll()
        cacheLock.unlock()
    }

    static func build(
        text: String,
        fontSize: CGFloat,
        textColor: Color,
        projectRoot: String? = nil,
        codeSettings: CodeDisplaySettings = .default,
        isLightInterface: Bool = Color.mimo.isLightTheme
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let baseColor = NSColor(textColor)
        let interfacePalette = InterfacePalette(isLight: isLightInterface)
        let muted = interfacePalette.muted
        let brand = interfacePalette.brand
        let codePalette = codeSettings.theme(isLightInterface: isLightInterface).palette
        let codeBackground = NSColor(codePalette.background)
        let codeHeaderBackground = NSColor(codePalette.headerBackground)
        let border = interfacePalette.border

        let baseFont = NSFont.systemFont(ofSize: fontSize)
        let codeFont = NSFont.monospacedSystemFont(ofSize: max(10, fontSize - 1), weight: .regular)
        let captionFont = NSFont.systemFont(ofSize: max(9, fontSize - 4), weight: .semibold)

        let blocks = MarkdownDocumentParser.parse(text)
        for (index, block) in blocks.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n"))
            }
            switch block {
            case .heading(let level, let content):
                let size = fontSize + (level == 1 ? 4 : (level == 2 ? 2 : 0))
                let font = NSFont.systemFont(ofSize: size, weight: .bold)
                result.append(NSAttributedString(string: content, attributes: [
                    .font: font,
                    .foregroundColor: baseColor
                ]))

            case .paragraph(let content):
                appendInline(content, to: result, font: baseFont, color: baseColor,
                             codeFont: codeFont, brand: brand, projectRoot: projectRoot)

            case .bulletItem(let content):
                result.append(NSAttributedString(string: "• ", attributes: [
                    .font: baseFont,
                    .foregroundColor: muted
                ]))
                appendInline(content, to: result, font: baseFont, color: baseColor,
                             codeFont: codeFont, brand: brand, projectRoot: projectRoot)

            case .numberedItem(let number, let content):
                result.append(NSAttributedString(string: "\(number). ", attributes: [
                    .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
                    .foregroundColor: interfacePalette.thinking
                ]))
                appendInline(content, to: result, font: baseFont, color: baseColor,
                             codeFont: codeFont, brand: brand, projectRoot: projectRoot)

            case .checkbox(let isChecked, let content):
                result.append(NSAttributedString(string: isChecked ? "☑ " : "☐ ", attributes: [
                    .font: baseFont,
                    .foregroundColor: interfacePalette.thinking
                ]))
                appendInline(content, to: result, font: baseFont, color: baseColor,
                             codeFont: codeFont, brand: brand, projectRoot: projectRoot)

            case .blockquote(let content):
                result.append(NSAttributedString(string: "│ ", attributes: [
                    .font: baseFont,
                    .foregroundColor: brand.withAlphaComponent(0.4)
                ]))
                appendInline(content, to: result, font: baseFont, color: muted,
                             codeFont: codeFont, brand: brand, projectRoot: projectRoot)

            case .inlineCode(let code):
                result.append(NSAttributedString(string: code, attributes: [
                    .font: codeFont,
                    .foregroundColor: brand
                ]))

            case .bold(let content):
                result.append(NSAttributedString(string: content, attributes: [
                    .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
                    .foregroundColor: baseColor
                ]))

            case .horizontalRule:
                result.append(NSAttributedString(string: String(repeating: "─", count: 32), attributes: [
                    .font: baseFont,
                    .foregroundColor: border
                ]))

            case .codeBlock(let language, let code):
                let caption = language.isEmpty
                    ? "CODE"
                    : CodeLanguageLabel.name(for: language).uppercased()
                result.append(NSAttributedString(string: caption, attributes: [
                    .font: captionFont,
                    .foregroundColor: NSColor(codePalette.lineNumber),
                    .backgroundColor: codeHeaderBackground
                ]))
                result.append(NSAttributedString(string: "\n"))
                let highlighted = NSMutableAttributedString(attributedString: CodeSyntaxHighlighter.nsAttributed(
                    code,
                    language: language,
                    palette: codePalette,
                    fontSize: codeSettings.clampedFontSize
                ))
                if highlighted.length > 0 {
                    highlighted.addAttribute(
                        .backgroundColor,
                        value: codeBackground,
                        range: NSRange(location: 0, length: highlighted.length)
                    )
                }
                result.append(highlighted)

            case .table(let rows):
                appendTable(rows, to: result, font: codeFont, color: baseColor, muted: muted)

            case .math(let latex):
                result.append(NSAttributedString(string: LaTeXMathRenderer.render(latex), attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: min(fontSize + 1, 18), weight: .regular),
                    .foregroundColor: baseColor
                ]))
            }
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        paragraph.paragraphSpacing = 6
        paragraph.defaultTabInterval = 18
        result.addAttributes([.paragraphStyle: paragraph], range: NSRange(location: 0, length: result.length))
        return result
    }

    private static func appendInline(
        _ content: String,
        to result: NSMutableAttributedString,
        font: NSFont,
        color: NSColor,
        codeFont: NSFont,
        brand: NSColor,
        projectRoot: String?
    ) {
        for part in MarkdownInlineParser.parse(content) {
            switch part {
            case .text(let value):
                appendTextWithFilePaths(value, to: result, font: font, color: color, projectRoot: projectRoot)
            case .bold(let value):
                let boldFont = NSFont.systemFont(ofSize: font.pointSize, weight: .bold)
                appendTextWithFilePaths(value, to: result, font: boldFont, color: color, projectRoot: projectRoot)
            case .italic(let value):
                let italic = NSFontManager.shared.convert(
                    NSFont.systemFont(ofSize: font.pointSize),
                    toHaveTrait: .italicFontMask
                )
                appendTextWithFilePaths(value, to: result, font: italic, color: color, projectRoot: projectRoot)
            case .code(let value):
                let codeAttributes: [NSAttributedString.Key: Any] = [
                    .font: codeFont,
                    .foregroundColor: brand,
                    .backgroundColor: brand.withAlphaComponent(0.12)
                ]
                let attributedCode = NSMutableAttributedString(string: value, attributes: codeAttributes)
                if let resolved = ChatFileOpenLogic.resolveFilePath(value, projectRoot: projectRoot) {
                    attributedCode.addAttribute(.chatFilePath, value: resolved, range: NSRange(location: 0, length: attributedCode.length))
                }
                result.append(attributedCode)
            case .link(let title, let url):
                result.append(NSAttributedString(string: title, attributes: [
                    .font: font,
                    .foregroundColor: brand,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .link: url
                ]))
            case .mathInline(let value):
                let italic = NSFontManager.shared.convert(
                    codeFont,
                    toHaveTrait: .italicFontMask
                )
                result.append(NSAttributedString(string: value, attributes: [
                    .font: italic,
                    .foregroundColor: color,
                    .backgroundColor: brand.withAlphaComponent(0.06)
                ]))
            }
        }
    }

    /// Appends plain text while marking any substring that resolves to an
    /// existing file/folder (relative to the project root or absolute) with
    /// `.chatFilePath` so a click opens the "Open with / Reveal in Finder"
    /// menu. The visual style stays the surrounding text style — file names
    /// outside inline code do not get repainted (user request 2026-10-31).
    private static func appendTextWithFilePaths(
        _ value: String,
        to result: NSMutableAttributedString,
        font: NSFont,
        color: NSColor,
        projectRoot: String?
    ) {
        let ns = value as NSString
        guard ns.length > 0 else { return }
        // Potential path tokens are contiguous non-whitespace runs.
        guard let regex = try? NSRegularExpression(pattern: #"\S+"#) else {
            result.append(NSAttributedString(string: value, attributes: [.font: font, .foregroundColor: color]))
            return
        }
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        var last = 0
        for match in regex.matches(in: value, options: [], range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > last {
                result.append(NSAttributedString(
                    string: ns.substring(with: NSRange(location: last, length: match.range.location - last)),
                    attributes: baseAttributes
                ))
            }
            let token = ns.substring(with: match.range)
            var attributes = baseAttributes
            if let resolved = ChatFileOpenLogic.resolveFilePath(token, projectRoot: projectRoot) {
                attributes[.chatFilePath] = resolved
            }
            result.append(NSAttributedString(string: token, attributes: attributes))
            last = match.range.location + match.range.length
        }
        if last < ns.length {
            result.append(NSAttributedString(
                string: ns.substring(with: NSRange(location: last, length: ns.length - last)),
                attributes: baseAttributes
            ))
        }
    }

    private static func appendTable(
        _ rows: [[String]],
        to result: NSMutableAttributedString,
        font: NSFont,
        color: NSColor,
        muted: NSColor
    ) {
        guard !rows.isEmpty else { return }
        let columnCount = max(rows.map(\.count).max() ?? 1, 1)
        var widths = Array(repeating: 0, count: columnCount)
        for row in rows {
            for column in 0..<columnCount {
                let value = column < row.count ? row[column] : ""
                widths[column] = max(widths[column], value.count)
            }
        }

        for (rowIndex, row) in rows.enumerated() {
            var line = ""
            for column in 0..<columnCount {
                let value = column < row.count ? row[column] : ""
                let padded = value.padding(toLength: widths[column], withPad: " ", startingAt: 0)
                line += padded
                if column < columnCount - 1 { line += "  " }
            }
            let isHeader = rowIndex == 0
            result.append(NSAttributedString(string: line, attributes: [
                .font: isHeader ? NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .semibold) : font,
                .foregroundColor: isHeader ? color : muted
            ]))
            if rowIndex < rows.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
        }
    }

    /// Height of the laid-out text for a given width.
    static func measuredHeight(for textView: NSTextView, width: CGFloat) -> CGFloat {
        guard width > 0,
              let container = textView.textContainer,
              let layoutManager = textView.layoutManager else { return 0 }
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: container)
        let containerBoundingRect = layoutManager.usedRect(for: container)
        let insets = textView.textContainerInset
        let height = ceil(containerBoundingRect.height) + insets.height * 2
        textView.setFrameSize(NSSize(width: width, height: max(height, 1)))
        return max(height, 1)
    }
}
