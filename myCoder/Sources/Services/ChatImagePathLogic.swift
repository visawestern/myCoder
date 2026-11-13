import Foundation

/// Pure extraction of image paths from a message's text (plan item 13.1).
///
/// A token is an "image path" when:
///   • it looks like a file path (`ChatFileOpenLogic.looksLikeFilePath`);
///   • the path resolves to an EXISTING file (relative → project root);
///   • the file extension is one of the known image extensions.
///
/// The result is used by `ChatImagePathCollageView` to render inline
/// thumbnails under the message text.
///
/// Input: message text, project root (for relative paths), a result bound.
/// Output: ordered, deduplicated absolute paths of existing images.
/// Dependencies: `ChatFileOpenLogic` (detection/resolution).
enum ChatImagePathLogic {

    /// Image extensions rendered inline as previews.
    static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "bmp", "heic", "tiff", "svg"
    ]

    /// How many image paths are extracted per message at most.
    static let maxInlineImages = 6

    /// Extract image paths from free text.
    ///
    /// Input: text; project root; optional bound; optional cache.
    /// Output: unique resolved absolute paths of existing image files.
    /// Dependencies: `ChatImagePathExtractionCache` (memoization),
    /// `ChatFileOpenLogic.resolveFilePath`, `imageExtensions`.
    static func extractImagePaths(from text: String,
                                  projectRoot: String?,
                                  limit: Int = maxInlineImages,
                                  cache: ChatImagePathExtractionCache = .shared) -> [String] {
        cache.extractedPaths(from: text, projectRoot: projectRoot, limit: limit)
    }

    /// Pure resolution core (no caching): maps tokens to existing image paths.
    ///
    /// Input: text; project root; result bound; a resolver that converts a
    /// token into a resolved absolute path (or nil).
    /// Output: ordered, deduplicated absolute paths of existing images.
    /// Dependencies: none — the resolver is injected, so this core is portable
    /// and testable without touching the filesystem.
    static func resolvedPaths(in text: String,
                              projectRoot: String?,
                              limit: Int,
                              resolve: (String) -> String?) -> [String] {
        guard !text.isEmpty else { return [] }
        var seen = Set<String>()
        var result: [String] = []
        for token in tokenize(text) where result.count < limit {
            guard let path = resolve(token) else { continue }
            let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
            guard imageExtensions.contains(ext), seen.insert(path).inserted else { continue }
            result.append(path)
        }
        return result
    }

    /// Split text into candidate path tokens (whitespace/newline separated,
    /// trailing punctuation trimmed by the resolver).
    private static func tokenize(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet.whitespacesAndNewlines)
    }
}
