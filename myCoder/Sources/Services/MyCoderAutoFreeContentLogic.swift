import Foundation

enum MyCoderAutoFreeContentPart: Codable, Equatable {
    case text(String)
    case imageURL(String)
    case fileText(name: String, content: String)

    private enum CodingKeys: String, CodingKey {
        case type, text, imageURL = "image_url", name, content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try container.decode(String.self, forKey: .text))
        case "image_url":
            let image = try container.decode([String: String].self, forKey: .imageURL)
            self = .imageURL(try image.value(for: "url"))
        case "file_text":
            self = .fileText(
                name: try container.decode(String.self, forKey: .name),
                content: try container.decode(String.self, forKey: .content)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown Auto Free content part type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value):
            try container.encode("text", forKey: .type)
            try container.encode(value, forKey: .text)
        case .imageURL(let url):
            try container.encode("image_url", forKey: .type)
            try container.encode(["url": url], forKey: .imageURL)
        case .fileText(let name, let content):
            // OpenAI-compatible providers do not share one file-part schema;
            // encode readable files as text so their contents still reach the
            // coding model, while preserving the filename in the text.
            try container.encode("text", forKey: .type)
            try container.encode("[Attached file: \(name)]\n\(content)", forKey: .text)
        }
    }
}

struct MyCoderAutoFreeTextFile: Equatable {
    let name: String
    let content: String
}

enum MyCoderAutoFreeContentLogic {
    /// Returns true when the anonymous OpenAI-compatible route must not attempt
    /// UTF-8 text fallback for an attachment. Unknown text extensions remain
    /// eligible for bounded decoding; the caller still validates UTF-8.
    static func isUnsupportedForTextRoute(fileName: String, mimeType: String) -> Bool {
        let ext = (fileName as NSString).pathExtension.lowercased()
        let mime = mimeType.lowercased()
        if mime == "application/pdf" || ext == "pdf" { return true }
        let binaryExtensions: Set<String> = [
            "7z", "avi", "bin", "bz2", "dmg", "doc", "docx", "elf", "exe",
            "gz", "iso", "jar", "m4a", "mov", "mp3", "mp4", "ogg", "ppt",
            "pptx", "rar", "sqlite", "sqlite3", "tar", "wasm", "webm", "xls",
            "xlsx", "zip"
        ]
        if binaryExtensions.contains(ext) { return true }
        if mime == "application/octet-stream" {
            let knownTextExtensions: Set<String> = [
                "", "bash", "c", "cfg", "conf", "cpp", "csv", "env", "h", "hpp",
                "ini", "java", "js", "json", "log", "md", "php", "py", "rb", "rs",
                "sh", "sql", "toml", "ts", "tsx", "txt", "xml", "yaml", "yml"
            ]
            return !knownTextExtensions.contains(ext)
        }
        return false
    }

    static func parts(
        text: String,
        imageDataURLs: [String],
        textFiles: [MyCoderAutoFreeTextFile]
    ) -> [MyCoderAutoFreeContentPart] {
        var result: [MyCoderAutoFreeContentPart] = []
        if !text.isEmpty || (imageDataURLs.isEmpty && textFiles.isEmpty) {
            result.append(.text(text))
        }
        result.append(contentsOf: imageDataURLs.filter { !$0.isEmpty }.map(MyCoderAutoFreeContentPart.imageURL))
        result.append(contentsOf: textFiles.map {
            .fileText(name: $0.name, content: $0.content)
        })
        return result
    }
}

private extension Dictionary where Key == String, Value == String {
    func value(for key: String) throws -> String {
        guard let value = self[key] else {
            throw DecodingError.keyNotFound(
                AnyCodingKey(stringValue: key),
                .init(codingPath: [], debugDescription: "Missing image URL")
            )
        }
        return value
    }
}

private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
