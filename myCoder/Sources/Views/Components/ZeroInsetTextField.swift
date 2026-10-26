import SwiftUI
import AppKit

/// AppKit text field/editor with no leading inset — SwiftUI TextField adds ~20px on macOS.
struct ZeroInsetTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var multiline: Bool = false
    var fontSize: CGFloat = 14
    var minHeight: CGFloat = 24
    var maxHeight: CGFloat = 72
    var focusRequest: Int = 0
    var onSubmit: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    private func applyFocusIfRequested(to responder: NSView, context: Context) {
        guard focusRequest != context.coordinator.lastFocusRequest else { return }
        context.coordinator.lastFocusRequest = focusRequest
        DispatchQueue.main.async {
            responder.window?.makeFirstResponder(responder)
        }
    }

    func makeNSView(context: Context) -> NSView {
        if multiline {
            return makeScrollView(context: context)
        }
        return makeSingleLineField(context: context)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onSubmit = onSubmit

        if multiline, let scrollView = nsView as? NSScrollView,
           let textView = scrollView.documentView as? ZeroInsetTextView {
            syncTextView(textView, context: context)
            resizeMultilineScrollView(scrollView, textView: textView, proposedWidth: scrollView.bounds.width)
            applyFocusIfRequested(to: textView, context: context)
            return
        }

        if let field = nsView as? NSTextField {
            syncSingleLineField(field, context: context)
            applyFocusIfRequested(to: field, context: context)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        if multiline, let scrollView = nsView as? NSScrollView,
           let textView = scrollView.documentView as? NSTextView {
            let height = measuredMultilineHeight(textView: textView, width: width)
            return CGSize(width: width, height: height)
        }
        return CGSize(width: width, height: minHeight)
    }

    static func clampedHeight(usedHeight: CGFloat, pointSize: CGFloat, minHeight: CGFloat, maxHeight: CGFloat) -> CGFloat {
        let layoutHeight = max(usedHeight + 4, pointSize * 1.25)
        return min(max(layoutHeight, minHeight), maxHeight)
    }

    private func measuredMultilineHeight(textView: NSTextView, width: CGFloat) -> CGFloat {
        guard width > 0,
              let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager else {
            return minHeight
        }

        textContainer.containerSize = NSSize(width: max(width, 1), height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        let used = ceil(layoutManager.usedRect(for: textContainer).height)
        let pointSize = textView.font?.pointSize ?? fontSize
        return Self.clampedHeight(usedHeight: used, pointSize: pointSize, minHeight: minHeight, maxHeight: maxHeight)
    }

    private func resizeMultilineScrollView(_ scrollView: NSScrollView, textView: NSTextView, proposedWidth: CGFloat) {
        let width = proposedWidth > 0 ? proposedWidth : scrollView.bounds.width
        guard width > 0 else { return }
        let height = measuredMultilineHeight(textView: textView, width: width)
        if abs(scrollView.frame.height - height) > 0.5 {
            scrollView.frame.size.height = height
            textView.frame.size.height = max(height, textView.frame.height)
        }
    }

    private func makeSingleLineField(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: fontSize)
        field.placeholderString = placeholder
        field.lineBreakMode = .byTruncatingTail
        field.delegate = context.coordinator
        field.translatesAutoresizingMaskIntoConstraints = false
        if let cell = field.cell as? NSTextFieldCell {
            cell.usesSingleLineMode = true
            cell.wraps = false
            cell.isScrollable = true
        }
        return field
    }

    private func makeScrollView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = ZeroInsetTextView()
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.font = NSFont.systemFont(ofSize: fontSize)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.delegate = context.coordinator
        textView.string = text
        textView.onSubmit = onSubmit
        textView.placeholderString = placeholder

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    private func syncSingleLineField(_ field: NSTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
        if field.placeholderString != placeholder {
            field.placeholderString = placeholder
        }
        let targetSize = fontSize
        if field.font?.pointSize != targetSize {
            field.font = NSFont.systemFont(ofSize: targetSize)
        }
    }

    private func syncTextView(_ textView: ZeroInsetTextView, context: Context) {
        if textView.string != text {
            textView.string = text
        }
        if textView.placeholderString != placeholder {
            textView.placeholderString = placeholder
        }
        textView.onSubmit = onSubmit
        let targetSize = fontSize
        if textView.font?.pointSize != targetSize {
            textView.font = NSFont.systemFont(ofSize: targetSize)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate, NSTextViewDelegate {
        var text: Binding<String>
        var onSubmit: (() -> Void)?
        var lastFocusRequest: Int = 0
        fileprivate weak var textView: ZeroInsetTextView?

        init(text: Binding<String>, onSubmit: (() -> Void)?) {
            self.text = text
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            if let scrollView = textView.enclosingScrollView {
                scrollView.invalidateIntrinsicContentSize()
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if NSEvent.modifierFlags.contains(.shift) {
                    return false
                }
                onSubmit?()
                return true
            }
            return false
        }
    }
}

private final class ZeroInsetTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var placeholderString: String = ""

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholderString.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let inset = textContainerInset
        let rect = NSRect(
            x: inset.width,
            y: inset.height,
            width: bounds.width - inset.width * 2,
            height: bounds.height - inset.height * 2
        )
        placeholderString.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
    }

    override var string: String {
        didSet { needsDisplay = true }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36, !event.modifierFlags.contains(.shift) {
            onSubmit?()
            return
        }
        super.keyDown(with: event)
    }
}
