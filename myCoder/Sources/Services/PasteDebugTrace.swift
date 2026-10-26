import AppKit
import Foundation

enum PasteDebugSettings {
    /// Paste tracing is on only when `MIMO_DEBUG_PASTE=1`.
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["MIMO_DEBUG_PASTE"] == "1"
    }
}

enum PasteDebugTrace {
    static func log(_ source: String, _ message: String, store: MessageAttachmentStore? = nil) {
        guard PasteDebugSettings.isEnabled else { return }
        let line = "[\(source)] \(message)"
        fputs("MiMoPaste \(line)\n", stderr)
        guard let store else { return }
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                store.logPasteDebug(line)
            }
        } else {
            DispatchQueue.main.async {
                store.logPasteDebug(line)
            }
        }
    }

    static func describe(firstResponder: NSResponder?) -> String {
        guard let firstResponder else { return "firstResponder=nil" }
        return "firstResponder=\(String(describing: type(of: firstResponder)))"
    }

    static func describePasteboard(_ pb: NSPasteboard = .general) -> String {
        let types = pb.types?.map(\.rawValue).joined(separator: ", ") ?? "none"
        var parts: [String] = ["types=\(types)"]
        parts.append("hasAttachments=\(PasteboardAttachmentDetector.hasAttachments(on: pb))")

        let result = ClipboardProvider().consume(on: pb)
        parts.append("consumeImages=\(result.images.count)")
        parts.append("consumeFiles=\(result.files.count)")

        if let string = pb.string(forType: .string), !string.isEmpty {
            parts.append("stringChars=\(string.count)")
        }

        if let items = pb.pasteboardItems {
            for (index, item) in items.enumerated() {
                let itemTypes = item.types.map(\.rawValue).joined(separator: ", ")
                var sizes: [String] = []
                for type in item.types.prefix(8) {
                    if let data = item.data(forType: type) {
                        sizes.append("\(type.rawValue):\(data.count)b")
                    } else {
                        sizes.append("\(type.rawValue):promised")
                    }
                }
                parts.append("item\(index)[\(itemTypes)] {\(sizes.joined(separator: ", "))}")
            }
        }

        return parts.joined(separator: " | ")
    }
}

enum ChatPasteWindowSearch {
    static func attachmentTextView(in window: NSWindow?) -> AttachmentPasteTextView? {
        guard let root = window?.contentView else { return nil }
        return findAttachmentTextView(in: root)
    }

    private static func findAttachmentTextView(in view: NSView) -> AttachmentPasteTextView? {
        if let textView = view as? AttachmentPasteTextView {
            return textView
        }
        for subview in view.subviews {
            if let found = findAttachmentTextView(in: subview) {
                return found
            }
        }
        return nil
    }
}
