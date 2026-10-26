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
        let attributed = MarkdownAttributedStringBuilder.build(
            text: text,
            fontSize: scaledFontSize,
            textColor: textColor,
            projectRoot: projectRoot
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
        let height = MarkdownAttributedStringBuilder.measuredHeight(
            for: textView,
            width: width
        )
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
enum MarkdownAttributedStringBuilder {
    static func build(
        text: String,
        fontSize: CGFloat,
        textColor: Color,
        projectRoot: String? = nil
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let baseColor = NSColor(textColor)
        let muted = NSColor(Color.mimo.textMuted)
        let brand = NSColor(Color.mimo.brand)
        let codeBackground = NSColor(Color.mimo.codeBg)
        let codeHeaderBackground = NSColor(Color.mimo.codeHeaderBg)
        let border = NSColor(Color.mimo.border)

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
                    .foregroundColor: NSColor(Color.mimo.thinking)
                ]))
                appendInline(content, to: result, font: baseFont, color: baseColor,
                             codeFont: codeFont, brand: brand, projectRoot: projectRoot)

            case .checkbox(let isChecked, let content):
                result.append(NSAttributedString(string: isChecked ? "☑ " : "☐ ", attributes: [
                    .font: baseFont,
                    .foregroundColor: NSColor(Color.mimo.thinking)
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
                let caption = language.isEmpty ? "CODE" : language.uppercased()
                result.append(NSAttributedString(string: caption, attributes: [
                    .font: captionFont,
                    .foregroundColor: NSColor(Color.mimo.textMuted),
                    .backgroundColor: codeHeaderBackground
                ]))
                result.append(NSAttributedString(string: "\n"))
                result.append(NSAttributedString(string: code, attributes: [
                    .font: codeFont,
                    .foregroundColor: baseColor,
                    .backgroundColor: codeBackground
                ]))

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
                result.append(NSAttributedString(string: value, attributes: [
                    .font: font,
                    .foregroundColor: color
                ]))
            case .bold(let value):
                result.append(NSAttributedString(string: value, attributes: [
                    .font: NSFont.systemFont(ofSize: font.pointSize, weight: .bold),
                    .foregroundColor: color
                ]))
            case .italic(let value):
                let italic = NSFontManager.shared.convert(
                    NSFont.systemFont(ofSize: font.pointSize),
                    toHaveTrait: .italicFontMask
                )
                result.append(NSAttributedString(string: value, attributes: [
                    .font: italic,
                    .foregroundColor: color
                ]))
            case .code(let value):
                let codeAttributes: [NSAttributedString.Key: Any] = [
                    .font: codeFont,
                    .foregroundColor: brand,
                    .backgroundColor: brand.withAlphaComponent(0.12)
                ]
                let attributedCode = NSMutableAttributedString(string: value, attributes: codeAttributes)
                if ChatFileOpenLogic.looksLikeFilePath(value),
                   let resolved = ChatFileOpenLogic.resolveFilePath(value, projectRoot: projectRoot) {
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
