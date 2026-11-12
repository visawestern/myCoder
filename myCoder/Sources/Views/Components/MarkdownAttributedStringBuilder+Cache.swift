import SwiftUI
import AppKit

extension MarkdownAttributedStringBuilder {
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
                switch MarkdownLinkLogic.kind(for: url) {
                case .web:
                    result.append(NSAttributedString(string: title, attributes: [
                        .font: font,
                        .foregroundColor: brand,
                        .underlineStyle: NSUnderlineStyle.single.rawValue,
                        .link: url
                    ]))
                case .file:
                    var attributes: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: brand,
                        .underlineStyle: NSUnderlineStyle.single.rawValue
                    ]
                    // Локальный путь: клик открывает меню «Открыть с / Показать
                    // в Finder» (то же поведение, что у путей в тексте).
                    // Если файла нет — остаётся стиль ссылки без клика.
                    if let resolved = MarkdownLinkLogic.resolveFile(url, projectRoot: projectRoot) {
                        attributes[.chatFilePath] = resolved
                    }
                    result.append(NSAttributedString(string: title, attributes: attributes))
                case .unsupported:
                    result.append(NSAttributedString(string: title, attributes: [
                        .font: font,
                        .foregroundColor: color
                    ]))
                }
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
