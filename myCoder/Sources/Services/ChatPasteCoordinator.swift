@preconcurrency import AppKit

final class ChatPasteCoordinator {
    static let shared = ChatPasteCoordinator()

    private var monitor: Any?
    private var attachmentStore: MessageAttachmentStore?
    private var onInsertText: ((String) -> Void)?

    private init() {}

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard monitor == nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event) ?? event
        }

        fputs("MiMoPaste [coordinator] keyboard monitor installed\n", stderr)
    }

    func register(store: MessageAttachmentStore, onInsertText: @escaping (String) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        MainActor.assumeIsolated {
            attachmentStore = store
            self.onInsertText = onInsertText
            if PasteDebugSettings.isEnabled {
                store.logPasteDebug("Paste monitor ready — press ⌘V or Edit → Paste")
            }
        }
        fputs("MiMoPaste [coordinator] store registered\n", stderr)
    }

    func unregister(store: MessageAttachmentStore) {
        dispatchPrecondition(condition: .onQueue(.main))
        MainActor.assumeIsolated {
            guard attachmentStore === store else { return }
            attachmentStore = nil
            onInsertText = nil
        }
    }

    @discardableResult
    func performPaste() -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        let window = NSApp.keyWindow
        if shouldPassThrough(firstResponder: window?.firstResponder) {
            // Let the focused control paste normally via the responder chain.
            return NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
        }
        return handlePasteAction(source: "menu-paste", window: window)
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        dispatchPrecondition(condition: .onQueue(.main))
        guard event.modifierFlags.contains(.command),
              event.charactersIgnoringModifiers?.lowercased() == "v" else {
            return event
        }

        let responder = (event.window ?? NSApp.keyWindow)?.firstResponder
        if shouldPassThrough(firstResponder: responder) {
            return event
        }

        return handlePasteAction(source: "keyDown", window: event.window) ? nil : event
    }

    private func shouldPassThrough(firstResponder: NSResponder?) -> Bool {
        PasteRoutingDecision.shouldPassThrough(
            responder: PasteRoutingDecision.kind(of: firstResponder),
            pasteboardHasAttachments: PasteboardAttachmentDetector.hasAttachments()
        )
    }

    @discardableResult
    private func handlePasteAction(source: String, window: NSWindow?) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        let resolvedWindow = window ?? NSApp.keyWindow

        guard resolvedWindow?.isKeyWindow == true else {
            log(source, "skip: window not key", store: nil)
            return false
        }

        let firstResponder = resolvedWindow?.firstResponder
        if firstResponder is NSTextField || firstResponder is NSSecureTextField {
            log(source, "skip: sidebar/search field focused", store: nil)
            return false
        }

        return MainActor.assumeIsolated { () -> Bool in
            guard let store = attachmentStore else {
                log(source, "skip: no chat store registered", store: nil)
                fputs("MiMoPaste [coordinator] ERROR: chat store not registered — open chat panel\n", stderr)
                return true
            }

            log(
                source,
                "\(PasteDebugTrace.describe(firstResponder: firstResponder)) | \(PasteDebugTrace.describePasteboard())",
                store: store
            )

            if AttachmentImportExecutor.tryImportFromPasteboard(into: store) {
                log(source, "import OK images=\(store.attachedImages.count)", store: store)
                return true
            }

            if let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
                onInsertText?(text)
                log(source, "inserted text chars=\(text.count)", store: store)
                return true
            }

            if let textView = ChatPasteWindowSearch.attachmentTextView(in: resolvedWindow) {
                resolvedWindow?.makeFirstResponder(textView)
                if textView.performPasteFromPasteboard(source: source) {
                    log(source, "textView fallback OK", store: store)
                    return true
                }
            }

            store.importResult(ClipboardPasteResult(), showErrorOnEmpty: false)
            log(source, "FAILED — \(PasteDebugTrace.describePasteboard())", store: store)
            return true
        }
    }

    private func log(_ source: String, _ message: String, store: MessageAttachmentStore?) {
        PasteDebugTrace.log(source, message, store: store)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        ChatPasteCoordinator.shared.start()
    }
}
