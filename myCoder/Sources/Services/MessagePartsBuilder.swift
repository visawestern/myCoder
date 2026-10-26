import Foundation

enum MessagePartsBuilder {
    static func build(text: String, files: [FileInfo], images: [ClipboardImage]) -> [[String: Any]] {
        var parts: [[String: Any]] = []

        if !text.isEmpty {
            parts.append(["type": "text", "text": text])
        }

        for image in images {
            if let part = imagePart(for: image) {
                parts.append(part)
            }
        }

        for file in files {
            if let filePart = filePart(for: file) {
                parts.append(filePart)
            }
        }

        if parts.isEmpty {
            parts.append(["type": "text", "text": ""])
        }

        return parts
    }

    static func imagePart(for image: ClipboardImage) -> [String: Any]? {
        guard !image.base64.isEmpty else { return nil }
        return [
            "type": "file",
            "mime": image.mimeType,
            "url": dataURL(mimeType: image.mimeType, base64: image.base64)
        ]
    }

    static func filePart(for file: FileInfo) -> [String: Any]? {
        guard let path = file.path, !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        var part: [String: Any] = [
            "type": "file",
            "mime": mimeType(for: file),
            "url": url.absoluteString
        ]
        part["filename"] = file.name
        return part
    }

    static func dataURL(mimeType: String, base64: String) -> String {
        "data:\(mimeType);base64,\(base64)"
    }

    static func base64FromDataURL(_ url: String) -> (mimeType: String, base64: String)? {
        guard url.hasPrefix("data:"), let commaIndex = url.firstIndex(of: ",") else { return nil }
        let header = url[url.index(url.startIndex, offsetBy: 5)..<commaIndex]
        let payload = String(url[url.index(after: commaIndex)...])
        guard header.hasSuffix(";base64") else { return nil }
        let mimeType = header.split(separator: ";", maxSplits: 1).first.map(String.init) ?? "application/octet-stream"
        guard !payload.isEmpty else { return nil }
        return (mimeType, payload)
    }

    static func isImageMimeType(_ mimeType: String) -> Bool {
        mimeType.lowercased().hasPrefix("image/")
    }

    static func mimeType(for file: FileInfo) -> String {
        switch file.type {
        case .swift: return "text/x-swift"
        case .python: return "text/x-python"
        case .javascript: return "text/javascript"
        case .typescript: return "text/typescript"
        case .css: return "text/css"
        case .html: return "text/html"
        case .json: return "application/json"
        case .yaml: return "application/yaml"
        case .markdown: return "text/markdown"
        case .dart: return "application/dart"
        case .unknown:
            let ext = (file.name as NSString).pathExtension.lowercased()
            if ext == "png" { return "image/png" }
            if ext == "jpg" || ext == "jpeg" { return "image/jpeg" }
            if ext == "gif" { return "image/gif" }
            if ext == "webp" { return "image/webp" }
            if ext == "pdf" { return "application/pdf" }
            return "application/octet-stream"
        }
    }

    /// Builds local message parts for the chat transcript UI.
    static func displayParts(text: String, images: [ClipboardImage]) -> [MessagePartContent] {
        var parts: [MessagePartContent] = []
        if !text.isEmpty {
            parts.append(.text(text))
        }
        for image in images where !image.base64.isEmpty {
            parts.append(.image(base64: image.base64, mimeType: image.mimeType))
        }
        return parts
    }
}
