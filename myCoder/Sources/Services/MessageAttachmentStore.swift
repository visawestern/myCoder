import Foundation
import SwiftUI

@MainActor
final class MessageAttachmentStore: ObservableObject {
    @Published private(set) var attachedImages: [ClipboardImage] = []
    @Published private(set) var attachedFiles: [FileInfo] = []
    @Published var lastImportError: String?
    @Published private(set) var lastPasteDebugLine: String?

    static let emptyClipboardMessage = "No image or file in clipboard."

    func logPasteDebug(_ line: String) {
        lastPasteDebugLine = line
    }

    func clearPasteDebug() {
        lastPasteDebugLine = nil
    }

    func importFromPasteboard(using provider: ClipboardProviding = ClipboardProvider()) {
        importResult(provider.consume(), showErrorOnEmpty: true)
    }

    func importResult(_ result: ClipboardPasteResult, showErrorOnEmpty: Bool = true) {
        guard !result.isEmpty else {
            if showErrorOnEmpty {
                lastImportError = Self.emptyClipboardMessage
            }
            return
        }

        lastImportError = nil
        var images = attachedImages
        var files = attachedFiles
        MessageAttachmentState.apply(result, images: &images, files: &files)
        attachedImages = images
        attachedFiles = files
    }

    func clear() {
        attachedImages = []
        attachedFiles = []
        lastImportError = nil
        lastPasteDebugLine = nil
    }

    func clearImportError() {
        lastImportError = nil
    }

    func replaceImages(_ images: [ClipboardImage]) {
        attachedImages = images
    }

    func replaceFiles(_ files: [FileInfo]) {
        attachedFiles = files
    }

    func appendFile(_ file: FileInfo) {
        if let path = file.path {
            guard !attachedFiles.contains(where: { $0.path == path }) else { return }
        }
        attachedFiles.append(file)
    }
}
