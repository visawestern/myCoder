import Foundation

/// Read-side helpers for the emulated file tools, split out of
/// `ProjectWebToolExecutor.swift` to keep that module inside the 600-line
/// budget. They are pure formatting/parsing functions with no executor state.
extension ProjectWebToolExecutor {

    /// MIME type for an image file extension (used by the ATTACHED_IMAGE
    /// protocol between readFile and the web driver).
    /// Input: file extension. Output: MIME string. Dependencies: none.
    static func imageMIME(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "bmp": return "image/bmp"
        case "tiff", "tif": return "image/tiff"
        default: return "image/png"
        }
    }

    /// Parse an ATTACHED_IMAGE result produced by `readFile` on an image.
    /// Input: tool result string. Output: (mime, raw bytes) for a well-formed
    /// marker, nil otherwise. Dependencies: none.
    static func parseAttachedImage(from result: String) -> (mime: String, data: Data)? {
        guard result.hasPrefix("ATTACHED_IMAGE:") else { return nil }
        let remainder = String(result.dropFirst("ATTACHED_IMAGE:".count))
        let parts = remainder.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              !parts[0].isEmpty,
              let data = Data(base64Encoded: String(parts[1])) else { return nil }
        return (String(parts[0]), data)
    }

    /// Line-windowed read (Claude Code Read parity): return lines
    /// [offset, offset+limit) 1-based with an explicit range header so the
    /// model knows exactly which window it got and can page further. The
    /// 8000-char web bound still applies inside the window.
    /// Input: full text, display path, 1-based offset, optional line limit.
    /// Output: header + window (bounded). Dependencies: none.
    static func windowedRead(_ content: String, path: String, offset: Int, limit: Int?) -> String {
        let lines = content.components(separatedBy: "\n")
        let total = lines.count
        let start = max(1, offset)
        guard start <= total else {
            return "error: offset \(start) is beyond the end of \(path) (\(total) lines)"
        }
        let end: Int
        if let limit = limit, limit > 0 {
            end = min(start + limit - 1, total)
        } else {
            end = total
        }
        let slice = lines[(start - 1)..<end].joined(separator: "\n")
        let header = "[\(path): lines \(start)–\(end) of \(total)]"
        let charCap = 8000
        guard slice.count > charCap else { return "\(header)\n\(slice)" }
        let head = String(slice.prefix(charCap))
        return "\(header)\n\(head)\n\n[truncated within window: showing first \(charCap) chars of lines \(start)–\(end). Narrow the window with limit/offset to read more.]"
    }

    /// Web-chat-friendly bounded read: vendor chats split large pastes into
    /// parts and free models answer EACH part instead of honoring the
    /// continuation header (audit: Kimi answered mid-split, killing the turn).
    /// 8000 chars keeps a tool_result within ~2 chunks; the range header
    /// tells the model exactly what it got so it can request the next window.
    /// Input: full text + display path. Output: text capped at 8000 chars with
    /// a truncation hint. Dependencies: none.
    static func webBoundedRead(_ content: String, path: String) -> String {
        let limit = 8000
        guard content.count > limit else { return content }
        let head = content.prefix(limit)
        let lineHint = content.count > limit
            ? "\n\n[truncated: lines 1–\(head.filter { $0 == "\n" }.count + 1) of \(content.filter { $0 == "\n" }.count + 1); file has \(content.count) chars total. Ask to read more with a wider range if needed.]"
            : ""
        return head + lineHint
    }
}
