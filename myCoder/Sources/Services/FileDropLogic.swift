import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum FileDropLogic {
    static let legacyFilenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")

    static let registeredPasteboardTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        .URL,
        legacyFilenamesType,
        .png,
        .tiff,
        NSPasteboard.PasteboardType("public.image"),
        NSPasteboard.PasteboardType("public.heic"),
        NSPasteboard.PasteboardType("public.jpeg")
    ]

    static let swiftUIUTTypes: [UTType] = [.fileURL, .image, .png, .jpeg, .tiff, .heic, .pdf, .plainText, .data]

    static func canAccept(pasteboard: NSPasteboard) -> Bool {
        !parse(pasteboard: pasteboard).isEmpty
    }

    static func canAccept(draggingInfo: NSDraggingInfo) -> Bool {
        canAccept(pasteboard: draggingInfo.draggingPasteboard)
    }

    static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        var urls: [URL] = []
        var seen = Set<String>()

        func append(_ url: URL) {
            guard url.isFileURL else { return }
            let key = url.standardizedFileURL.path
            guard seen.insert(key).inserted else { return }
            urls.append(url)
        }

        if let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in objects {
                append(url)
            }
        }

        if let paths = pasteboard.propertyList(forType: legacyFilenamesType) as? [String] {
            for path in paths {
                append(URL(fileURLWithPath: path))
            }
        }

        if let urlString = pasteboard.string(forType: .fileURL),
           let url = URL(string: urlString) {
            append(url)
        }

        return urls
    }

    static func parse(pasteboard: NSPasteboard) -> ClipboardPasteResult {
        let urls = fileURLs(from: pasteboard)
        if !urls.isEmpty {
            let fileResult = ClipboardPasteLogic.parseFileURLs(urls)
            if !fileResult.isEmpty {
                return fileResult
            }
        }

        let imageTypes: [(NSPasteboard.PasteboardType, String)] = [
            (.png, "image/png"),
            (.tiff, "image/tiff"),
            (NSPasteboard.PasteboardType("public.heic"), "image/heic"),
            (NSPasteboard.PasteboardType("public.jpeg"), "image/jpeg"),
            (NSPasteboard.PasteboardType("public.image"), "image/png")
        ]

        for (type, mimeType) in imageTypes {
            guard let data = pasteboard.data(forType: type),
                  let clipImage = ClipboardImage(imageData: data, mimeType: mimeType) else {
                continue
            }
            return ClipboardPasteResult(images: [clipImage])
        }

        if let image = NSImage(pasteboard: pasteboard),
           let clipImage = ClipboardImage.from(nsImage: image) {
            return ClipboardPasteResult(images: [clipImage])
        }

        return ClipboardPasteResult()
    }

    static func parse(draggingInfo: NSDraggingInfo) -> ClipboardPasteResult {
        parse(pasteboard: draggingInfo.draggingPasteboard)
    }

    static func dragOperation(for draggingInfo: NSDraggingInfo) -> NSDragOperation {
        canAccept(draggingInfo: draggingInfo) ? .copy : []
    }
}

enum MessageInputDropSupport {
    static func applyDrop(
        to store: MessageAttachmentStore,
        providers: [NSItemProvider]
    ) async {
        var collected = ClipboardPasteResult()

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
               let url = await loadFileURL(from: provider) {
                collected = merge(collected, with: ClipboardPasteLogic.parseFileURLs([url]))
                continue
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
               let data = await loadImageData(from: provider),
               let clipImage = ClipboardImage(imageData: data, mimeType: "image/png") {
                collected.images.append(clipImage)
            }
        }

        guard !collected.isEmpty else { return }
        let result = collected
        await MainActor.run {
            store.importResult(result)
        }
    }

    static func applyDrop(
        providers: [NSItemProvider],
        images: Binding<[ClipboardImage]>,
        files: Binding<[FileInfo]>
    ) async {
        var collected = ClipboardPasteResult()

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
               let url = await loadFileURL(from: provider) {
                collected = merge(collected, with: ClipboardPasteLogic.parseFileURLs([url]))
                continue
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
               let data = await loadImageData(from: provider),
               let clipImage = ClipboardImage(imageData: data, mimeType: "image/png") {
                collected.images.append(clipImage)
            }
        }

        guard !collected.isEmpty else { return }
        let result = collected
        await MainActor.run {
            MessageAttachmentState.apply(result, images: images, files: files)
        }
    }

    private static func merge(_ lhs: ClipboardPasteResult, with rhs: ClipboardPasteResult) -> ClipboardPasteResult {
        var merged = lhs
        merged.images.append(contentsOf: rhs.images)
        merged.files.append(contentsOf: rhs.files)
        return merged
    }

    private static func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                    return
                }
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                    return
                }
                if let string = item as? String,
                   let url = URL(string: string) {
                    continuation.resume(returning: url)
                    return
                }
                continuation.resume(returning: nil)
            }
        }
    }

    private static func loadImageData(from provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}
