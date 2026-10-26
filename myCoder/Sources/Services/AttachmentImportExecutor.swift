import Foundation

enum AttachmentImportExecutor {
    /// Attempts clipboard import; returns true when attachments were imported.
    @discardableResult
    static func tryImportFromPasteboard(into store: MessageAttachmentStore?) -> Bool {
        guard let store else { return false }
        let result = ClipboardProvider().consume()
        guard !result.isEmpty else { return false }
        importResult(result, into: store, showErrorOnEmpty: false)
        PasteDebugTrace.log("tryImport", "OK images=\(result.images.count)", store: store)
        return true
    }

    /// Runs attachment import immediately on the main actor (AppKit paste/drop callbacks).
    static func importFromPasteboard(into store: MessageAttachmentStore?) {
        guard let store else { return }
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                store.importFromPasteboard()
            }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    store.importFromPasteboard()
                }
            }
        }
    }

    static func importResult(
        _ result: ClipboardPasteResult,
        into store: MessageAttachmentStore?,
        showErrorOnEmpty: Bool = true
    ) {
        guard let store else { return }
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                store.importResult(result, showErrorOnEmpty: showErrorOnEmpty)
            }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    store.importResult(result, showErrorOnEmpty: showErrorOnEmpty)
                }
            }
        }
    }
}
