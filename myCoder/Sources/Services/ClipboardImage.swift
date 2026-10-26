import AppKit

protocol ClipboardProviding {
    func consume() -> ClipboardPasteResult
}

extension ClipboardProvider: ClipboardProviding {}

struct ClipboardImage: Identifiable, Sendable {
    let id = UUID()
    let base64: String
    let mimeType: String

    var pngData: Data {
        Data(base64Encoded: base64) ?? Data()
    }

    init(base64: String, mimeType: String = "image/png") {
        self.base64 = base64
        self.mimeType = mimeType
    }

    init(nsImage: NSImage) {
        if let encoded = Self.from(nsImage: nsImage) {
            self.base64 = encoded.base64
            self.mimeType = encoded.mimeType
        } else {
            self.base64 = ""
            self.mimeType = "image/png"
        }
    }

    init?(imageData: Data, mimeType: String) {
        guard !imageData.isEmpty else { return nil }
        if mimeType == "image/png", Self.hasPNGSignature(imageData) {
            self.base64 = imageData.base64EncodedString()
            self.mimeType = mimeType
            return
        }
        if mimeType == "image/tiff",
           let rep = NSBitmapImageRep(data: imageData),
           let png = rep.representation(using: .png, properties: [:]) {
            self.base64 = png.base64EncodedString()
            self.mimeType = "image/png"
            return
        }
        if let image = NSImage(data: imageData), let encoded = Self.from(nsImage: image) {
            self.base64 = encoded.base64
            self.mimeType = encoded.mimeType
            return
        }
        return nil
    }

    /// Guards against non-image payloads (e.g. plain text) being blindly
    /// base64-encoded as PNG when a pasteboard item mislabels its type.
    static func hasPNGSignature(_ data: Data) -> Bool {
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard data.count >= signature.count else { return false }
        return data.prefix(signature.count).elementsEqual(signature)
    }

    static func from(nsImage: NSImage) -> ClipboardImage? {
        for rep in nsImage.representations {
            guard let bitmap = rep as? NSBitmapImageRep,
                  let png = bitmap.representation(using: .png, properties: [:]),
                  !png.isEmpty else { continue }
            return ClipboardImage(base64: png.base64EncodedString(), mimeType: "image/png")
        }

        if let tiff = nsImage.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]),
           !png.isEmpty {
            return ClipboardImage(base64: png.base64EncodedString(), mimeType: "image/png")
        }

        if let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let rep = NSBitmapImageRep(cgImage: cgImage)
            if let png = rep.representation(using: .png, properties: [:]), !png.isEmpty {
                return ClipboardImage(base64: png.base64EncodedString(), mimeType: "image/png")
            }
        }

        return nil
    }
}

enum PasteboardIsolation {
    private static let lock = NSRecursiveLock()

    static func withExclusiveAccess<T>(_ work: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try work()
    }
}

class ClipboardProvider {
    func fetchImage() -> NSImage? {
        PasteboardIsolation.withExclusiveAccess {
            fetchImageUnsynchronized()
        }
    }

    func consume(on pasteboard: NSPasteboard = .general) -> ClipboardPasteResult {
        PasteboardIsolation.withExclusiveAccess {
            consumeUnsynchronized(from: pasteboard)
        }
    }

    func consume() -> ClipboardPasteResult {
        consume(on: .general)
    }

    private func fetchImageUnsynchronized() -> NSImage? {
        let pb = NSPasteboard.general

        if let image = NSImage(pasteboard: pb) {
            return image
        }

        if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first {
            return image
        }

        for type in imageTypes {
            if let data = pb.data(forType: type), let image = NSImage(data: data) {
                return image
            }
        }

        return nil
    }

    private func consumeUnsynchronized(from pb: NSPasteboard) -> ClipboardPasteResult {
        if let itemResult = consumeImageFromPasteboardItems(pb) {
            return itemResult
        }

        if let rawResult = consumeRawImageData(from: pb) {
            return rawResult
        }

        if let image = NSImage(pasteboard: pb), let clipImage = ClipboardImage.from(nsImage: image) {
            return ClipboardPasteResult(images: [clipImage])
        }

        // Materializes promised screenshot pasteboard items (Ctrl+Shift+Cmd+3 / screencapture).
        if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first,
           let clipImage = ClipboardImage.from(nsImage: image) {
            return ClipboardPasteResult(images: [clipImage])
        }

        if let imageFileResult = consumeImageFileURLs(from: pb) {
            return imageFileResult
        }

        if let scanned = consumeByScanningAllItemTypes(from: pb) {
            return scanned
        }

        if let nonImageFiles = consumeNonImageFileURLs(from: pb) {
            return nonImageFiles
        }

        #if DEBUG
        logEmptyConsume(from: pb)
        #endif

        return ClipboardPasteResult()
    }

    #if DEBUG
    private func logEmptyConsume(from pb: NSPasteboard) {
        let types = pb.types?.map(\.rawValue).joined(separator: ", ") ?? "none"
        print("[ClipboardProvider] empty consume; pasteboard types: \(types)")
    }
    #endif

    private func fileURLs(from pb: NSPasteboard) -> [URL] {
        var urls: [URL] = []
        if let items = pb.pasteboardItems {
            for item in items {
                if let urlString = item.string(forType: .fileURL) ?? item.string(forType: .URL),
                   let url = URL(string: urlString), url.isFileURL {
                    urls.append(url)
                }
            }
        }
        let objectURLs = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
        for url in objectURLs where url.isFileURL && !urls.contains(url) {
            urls.append(url)
        }
        return urls
    }

    private func consumeNonImageFileURLs(from pb: NSPasteboard) -> ClipboardPasteResult? {
        let urls = fileURLs(from: pb)
        guard !urls.isEmpty else { return nil }

        var files: [FileInfo] = []
        for url in urls where !ClipboardPasteLogic.isImageFile(url) {
            if let file = ClipboardPasteLogic.fileInfo(from: url) {
                files.append(file)
            }
        }
        return files.isEmpty ? nil : ClipboardPasteResult(files: files)
    }

    private func consumeImageFileURLs(from pb: NSPasteboard) -> ClipboardPasteResult? {
        let urls = fileURLs(from: pb).filter { ClipboardPasteLogic.isImageFile($0) }
        guard !urls.isEmpty else { return nil }
        let fileResult = ClipboardPasteLogic.parseFileURLs(urls)
        return fileResult.isEmpty ? nil : fileResult
    }

    private func consumeImageFromPasteboardItems(_ pb: NSPasteboard) -> ClipboardPasteResult? {
        guard let items = pb.pasteboardItems, !items.isEmpty else { return nil }

        for item in items {
            for (type, mimeType) in rawImageTypePairs {
                guard let data = item.data(forType: type),
                      let clipImage = ClipboardImage(imageData: data, mimeType: mimeType) else {
                    continue
                }
                return ClipboardPasteResult(images: [clipImage])
            }
        }

        return nil
    }

    private var imageTypes: [NSPasteboard.PasteboardType] {
        PasteboardAttachmentDetector.imagePasteboardTypes
    }

    private var rawImageTypePairs: [(NSPasteboard.PasteboardType, String)] {
        PasteboardAttachmentDetector.rawImageTypePairs
    }

    private func consumeRawImageData(from pb: NSPasteboard) -> ClipboardPasteResult? {
        for (type, mimeType) in rawImageTypePairs {
            guard let data = pb.data(forType: type),
                  let clipImage = ClipboardImage(imageData: data, mimeType: mimeType) else {
                continue
            }
            return ClipboardPasteResult(images: [clipImage])
        }

        return nil
    }

    private func consumeByScanningAllItemTypes(from pb: NSPasteboard) -> ClipboardPasteResult? {
        guard let items = pb.pasteboardItems else { return nil }

        for item in items {
            for type in item.types {
                // Only probe types that plausibly carry image data — scanning
                // text types would misroute pasted text as image attachments.
                guard PasteboardAttachmentDetector.looksLikeImageType(type) else { continue }
                guard let data = item.data(forType: type), data.count > 32 else { continue }

                if let image = NSImage(data: data),
                   let clipImage = ClipboardImage.from(nsImage: image) {
                    return ClipboardPasteResult(images: [clipImage])
                }

                let mime = inferredMimeType(for: type)
                if let clipImage = ClipboardImage(imageData: data, mimeType: mime) {
                    return ClipboardPasteResult(images: [clipImage])
                }
            }
        }

        return nil
    }

    private func inferredMimeType(for type: NSPasteboard.PasteboardType) -> String {
        let raw = type.rawValue.lowercased()
        if raw.contains("png") { return "image/png" }
        if raw.contains("jpeg") || raw.contains("jpg") { return "image/jpeg" }
        if raw.contains("heic") { return "image/heic" }
        if raw.contains("heif") { return "image/heif" }
        if raw.contains("tiff") { return "image/tiff" }
        return "image/png"
    }
}
