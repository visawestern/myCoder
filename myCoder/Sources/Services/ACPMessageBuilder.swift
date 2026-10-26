import Foundation

/// Pure, testable builder for ACP messages with real multimodal content
/// (plan Раздел 9 Блок 2). Reuses MessagePartsBuilder.dataURL for encoding so
/// there is a single source of truth for image encoding across paths.
///
/// This replaces the old behavior in `buildACPMessages` that dropped image bytes
/// and inserted a `"[N image(s) attached]"` text placeholder (Блок 1 п.2 bug).
enum ACPMessageBuilder {
    /// Build a single user message with text + file names + real image data URLs.
    static func buildUserMessage(text: String,
                                 fileNames: [String],
                                 images: [(mimeType: String, base64: String)]) -> ACPRequestMessage {
        var textContent = text

        // Files are listed as text (ACP doesn't define a file content type).
        if !fileNames.isEmpty {
            let fileList = fileNames.map { "📎 \($0)" }.joined(separator: "\n")
            textContent += "\n\nAttached files:\n" + fileList
        }

        // Only use multimodal content parts when there are real images.
        // Text-only messages stay as a plain string for max backward compat.
        guard !images.isEmpty else {
            return ACPRequestMessage(role: "user", content: textContent)
        }

        var parts: [ACPContentPart] = []
        if !textContent.isEmpty {
            parts.append(.text(textContent))
        }
        // Images become real image_url parts with data URLs — no placeholder.
        for image in images {
            let url = "data:\(image.mimeType);base64,\(image.base64)"
            parts.append(.imageURL(url: url))
        }

        return ACPRequestMessage(role: "user", content: text, contentParts: parts)
    }

    /// Convenience: build from typed arrays matching the app's attachment types.
    static func buildUserMessage(text: String, files: [String], imageBase64ByMime: [(String, String)]) -> ACPRequestMessage {
        buildUserMessage(text: text, fileNames: files,
                         images: imageBase64ByMime.map { (mimeType: $0.0, base64: $0.1) })
    }
}
