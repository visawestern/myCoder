import Foundation
import AppKit
import SwiftUI

struct ClipboardPasteResult {
    var images: [ClipboardImage] = []
    var files: [FileInfo] = []

    var isEmpty: Bool {
        images.isEmpty && files.isEmpty
    }
}

enum ClipboardPasteLogic {
    static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "tiff", "tif"
    ]

    static func isImageFile(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    static func fileInfo(from url: URL) -> FileInfo? {
        guard url.isFileURL else { return nil }
        let name = url.lastPathComponent
        guard !name.isEmpty else { return nil }
        return FileInfo(
            name: name,
            type: FileType.from(ext: url.pathExtension),
            path: url.path
        )
    }

    static func imageFromFileURL(_ url: URL) -> ClipboardImage? {
        guard isImageFile(url) else { return nil }
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard let data = try? Data(contentsOf: url),
              let nsImage = NSImage(data: data) else {
            return nil
        }
        let clipImage = ClipboardImage(nsImage: nsImage)
        return clipImage.base64.isEmpty ? nil : clipImage
    }

    static func parseFileURLs(_ urls: [URL]) -> ClipboardPasteResult {
        var result = ClipboardPasteResult()
        for url in urls {
            if let image = imageFromFileURL(url) {
                result.images.append(image)
            } else if isImageFile(url) {
                continue
            } else if let file = fileInfo(from: url) {
                result.files.append(file)
            }
        }
        return result
    }
}

enum MessageAttachmentState {
    static func apply(
        _ result: ClipboardPasteResult,
        images: inout [ClipboardImage],
        files: inout [FileInfo]
    ) {
        images.append(contentsOf: result.images)
        for file in result.files {
            if let path = file.path {
                guard !files.contains(where: { $0.path == path }) else { continue }
            } else {
                guard !files.contains(where: { $0.name == file.name && $0.path == nil }) else { continue }
            }
            files.append(file)
        }
    }

    static func apply(
        _ result: ClipboardPasteResult,
        images: Binding<[ClipboardImage]>,
        files: Binding<[FileInfo]>
    ) {
        guard !result.isEmpty else { return }
        var nextImages = images.wrappedValue
        var nextFiles = files.wrappedValue
        apply(result, images: &nextImages, files: &nextFiles)
        images.wrappedValue = nextImages
        files.wrappedValue = nextFiles
    }
}

enum MessageSendValidation {
    static func canSend(text: String, images: [ClipboardImage], files: [FileInfo]) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !images.isEmpty
            || !files.isEmpty
    }
}
