import SwiftUI
import AppKit
import UniformTypeIdentifiers

private protocol AttachmentImportHandling: AnyObject {}

private extension AttachmentImportHandling where Self: NSView {
    func registerAttachmentDropTypes() {
        registerForDraggedTypes(FileDropLogic.registeredPasteboardTypes)
    }

    func attachmentDragOperation(for sender: NSDraggingInfo) -> NSDragOperation {
        FileDropLogic.dragOperation(for: sender)
    }
}

final class AttachmentPasteTextView: NSTextView, AttachmentImportHandling {
    var onImportFromPasteboard: (() -> Void)?
    var onImportResult: ((ClipboardPasteResult) -> Void)?
    var onSubmit: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let operation = attachmentDragOperation(for: sender)
        return operation == [] ? super.draggingEntered(sender) : operation
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let operation = attachmentDragOperation(for: sender)
        return operation == [] ? super.draggingUpdated(sender) : operation
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let result = FileDropLogic.parse(draggingInfo: sender)
        if !result.isEmpty {
            onImportResult?(result)
            return true
        }
        return super.performDragOperation(sender)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              event.charactersIgnoringModifiers?.lowercased() == "v" else {
            return super.performKeyEquivalent(with: event)
        }
        handlePasteCommand(source: "textView-cmdV")
        return true
    }

    override func paste(_ sender: Any?) {
        if handlePasteCommand(source: "textView-paste") {
            return
        }
        super.paste(sender)
    }

    @discardableResult
    private func handlePasteCommand(source: String) -> Bool {
        if tryImportAttachments(source: source) {
            return true
        }
        if performPasteFromPasteboard(source: "\(source)-text") {
            return true
        }
        onImportResult?(ClipboardPasteResult())
        PasteDebugTrace.log(source, "empty clipboard — showing error banner")
        return false
    }

    @discardableResult
    func performPasteFromPasteboard(source: String = "textView") -> Bool {
        let pb = NSPasteboard.general
        if let string = pb.string(forType: .string), !string.isEmpty {
            insertText(string, replacementRange: selectedRange())
            PasteDebugTrace.log(source, "inserted text chars=\(string.count)")
            return true
        }
        return false
    }

    @discardableResult
    private func tryImportAttachments(source: String) -> Bool {
        let result = ClipboardProvider().consume()
        PasteDebugTrace.log(
            source,
            "consume images=\(result.images.count) files=\(result.files.count) | \(PasteDebugTrace.describePasteboard())"
        )
        guard !result.isEmpty else { return false }
        if let onImportResult {
            onImportResult(result)
        } else {
            onImportFromPasteboard?()
        }
        return true
    }

    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        if tryImportAttachments(source: "textView-readSelection") {
            return true
        }
        return super.readSelection(from: pboard, type: type)
    }

    override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Any? {
        guard let returnType else {
            return super.validRequestor(forSendType: sendType, returnType: returnType)
        }
        if PasteboardAttachmentDetector.imagePasteboardTypes.contains(returnType) {
            return self
        }
        return super.validRequestor(forSendType: sendType, returnType: returnType)
    }

    static func pasteboardHasAttachmentsForKeyboard() -> Bool {
        PasteboardAttachmentDetector.hasAttachments()
    }
}

final class AttachmentPasteScrollView: NSScrollView, AttachmentImportHandling {
    var onImportFromPasteboard: (() -> Void)?
    var onImportResult: ((ClipboardPasteResult) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        attachmentDragOperation(for: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        attachmentDragOperation(for: sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let result = FileDropLogic.parse(draggingInfo: sender)
        if !result.isEmpty {
            onImportResult?(result)
            return true
        }
        if let textView = documentView as? AttachmentPasteTextView {
            return textView.performDragOperation(sender)
        }
        return false
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              event.charactersIgnoringModifiers?.lowercased() == "v",
              let textView = documentView as? AttachmentPasteTextView else {
            return super.performKeyEquivalent(with: event)
        }
        window?.makeFirstResponder(textView)
        return textView.performKeyEquivalent(with: event)
    }

    func importAttachmentsFromPasteboard() {
        let result = ClipboardProvider().consume()
        if !result.isEmpty {
            if let onImportResult {
                onImportResult(result)
            } else {
                onImportFromPasteboard?()
            }
            return
        }
        if let textView = documentView as? AttachmentPasteTextView {
            textView.paste(nil)
        }
    }
}

struct PasteAwareMessageTextField: View {
    @Environment(\.interfaceFontScale) private var interfaceFontScale
    @ObservedObject var attachmentStore: MessageAttachmentStore
    @Binding var text: String
    let placeholder: String
    var onSubmit: (() -> Void)? = nil
    var requestFocus: Bool = false
    var focusRequest: Int = 0
    var compact: Bool = false

    private var fieldHeight: CGFloat {
        compact
            ? InputLayout.compactTextHeight
            : InputLayout.textMaxHeight
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .interfaceFont(size: 14)
                    .foregroundColor(Color.mimo.textMuted)
                    .padding(.top, compact ? 8 : 2)
                    .allowsHitTesting(false)
            }

            PasteAwareTextEditor(
                text: $text,
                attachmentStore: attachmentStore,
                onSubmit: onSubmit,
                requestFocus: requestFocus,
                focusRequest: focusRequest,
                fontScale: interfaceFontScale,
                compact: compact
            )
        }
        .frame(
            maxWidth: .infinity,
            minHeight: compact ? InputLayout.compactTextHeight : InputLayout.textMinHeight,
            maxHeight: fieldHeight,
            alignment: .topLeading
        )
    }
}

private struct PasteAwareTextEditor: NSViewRepresentable {
    @Binding var text: String
    @ObservedObject var attachmentStore: MessageAttachmentStore
    var onSubmit: (() -> Void)?
    var requestFocus: Bool
    var focusRequest: Int
    var fontScale: CGFloat
    var compact: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(attachmentStore: attachmentStore)
    }

    func makeNSView(context: Context) -> AttachmentPasteScrollView {
        let scrollView = AttachmentPasteScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = !compact
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.registerAttachmentDropTypes()

        let textView = AttachmentPasteTextView()
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.font = NSFont.systemFont(
            ofSize: InterfaceTypography.scaled(14, scale: fontScale)
        )
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 0, height: compact ? 6 : 2)
        textView.isVerticallyResizable = !compact
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: compact ? InputLayout.compactTextHeight : CGFloat.greatestFiniteMagnitude
        )
        textView.delegate = context.coordinator
        textView.string = text
        textView.onSubmit = onSubmit

        scrollView.documentView = textView
        scrollView.registerAttachmentDropTypes()
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.syncBindings(
            text: $text,
            onSubmit: onSubmit,
            textView: textView,
            scrollView: scrollView
        )
        return scrollView
    }

    func updateNSView(_ scrollView: AttachmentPasteScrollView, context: Context) {
        guard let textView = scrollView.documentView as? AttachmentPasteTextView else { return }

        context.coordinator.syncBindings(
            text: $text,
            onSubmit: onSubmit,
            textView: textView,
            scrollView: scrollView
        )

        scrollView.hasVerticalScroller = !compact
        textView.isVerticallyResizable = !compact
        textView.textContainerInset = NSSize(width: 0, height: compact ? 6 : 2)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: compact ? InputLayout.compactTextHeight : CGFloat.greatestFiniteMagnitude
        )

        let scaledFontSize = InterfaceTypography.scaled(14, scale: fontScale)
        if textView.font?.pointSize != scaledFontSize {
            textView.font = NSFont.systemFont(ofSize: scaledFontSize)
        }

        if textView.string != text {
            textView.string = text
        }

        if focusRequest != context.coordinator.lastFocusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async {
                scrollView.window?.makeFirstResponder(textView)
            }
        } else if requestFocus && !context.coordinator.didApplyInitialFocus {
            context.coordinator.didApplyInitialFocus = true
            DispatchQueue.main.async {
                scrollView.window?.makeFirstResponder(textView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private var textBinding: Binding<String>?
        private let attachmentStore: MessageAttachmentStore
        var lastFocusRequest: Int = -1
        var didApplyInitialFocus = false
        weak var textView: NSTextView?
        weak var scrollView: AttachmentPasteScrollView?

        init(attachmentStore: MessageAttachmentStore) {
            self.attachmentStore = attachmentStore
        }

        func syncBindings(
            text: Binding<String>,
            onSubmit: (() -> Void)?,
            textView: AttachmentPasteTextView,
            scrollView: AttachmentPasteScrollView
        ) {
            textBinding = text
            self.scrollView = scrollView
            textView.onSubmit = onSubmit

            let importFromPasteboard: () -> Void = { [attachmentStore] in
                AttachmentImportExecutor.importFromPasteboard(into: attachmentStore)
            }
            let importResult: (ClipboardPasteResult) -> Void = { [attachmentStore] result in
                AttachmentImportExecutor.importResult(result, into: attachmentStore)
            }
            textView.onImportFromPasteboard = importFromPasteboard
            textView.onImportResult = importResult
            scrollView.onImportFromPasteboard = importFromPasteboard
            scrollView.onImportResult = importResult
        }

        func textDidChange(_ notification: Notification) {
            guard let textView, let textBinding else { return }
            textBinding.wrappedValue = textView.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSText.paste(_:)) else { return false }
            return AttachmentImportExecutor.tryImportFromPasteboard(into: attachmentStore)
        }
    }
}

enum MessageInputPasteSupport {
    static let pasteTypes: [UTType] = [.image, .fileURL, .png, .jpeg, .tiff, .heic, .pdf]

    static func applyPasteFromClipboard(
        images: Binding<[ClipboardImage]>,
        files: Binding<[FileInfo]>
    ) {
        let result = ClipboardProvider().consume()
        MessageAttachmentState.apply(result, images: images, files: files)
    }
}

extension MessageAttachmentStore {
    var imagesBinding: Binding<[ClipboardImage]> {
        Binding(
            get: { self.attachedImages },
            set: { self.replaceImages($0) }
        )
    }

    var filesBinding: Binding<[FileInfo]> {
        Binding(
            get: { self.attachedFiles },
            set: { self.replaceFiles($0) }
        )
    }
}
