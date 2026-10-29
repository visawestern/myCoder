import Foundation

/// One visual piece of a markdown answer: prose rendered as a selectable text
/// surface, or a fenced code block rendered as its own code spoiler.
enum MarkdownDisplaySegment: Equatable {
    case prose(String)
    case code(language: String, code: String)
}

/// Splits markdown into prose and fenced code blocks **in document order**.
///
/// The chat used to hand the whole message to one `NSTextView`, which can
/// only paint code as flat monospaced text. A code spoiler is a SwiftUI view,
/// so the message has to be split at fences first; everything outside fences
/// keeps the existing selectable renderer.
enum MarkdownCodeSegmentLogic {
    static func segments(from text: String) -> [MarkdownDisplaySegment] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let lines = text.components(separatedBy: "\n")
        var segments: [MarkdownDisplaySegment] = []
        var prose: [String] = []
        var index = 0

        func flushProse() {
            guard !prose.isEmpty else { return }
            let joined = prose.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            prose.removeAll()
            guard !joined.isEmpty else { return }
            segments.append(.prose(joined))
        }

        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix("```") {
                flushProse()
                let language = String(line.dropFirst(3))
                    .trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                index += 1
                // A streaming answer can end mid-block, so an unclosed fence
                // is rendered as code too instead of leaking back to prose.
                while index < lines.count && !lines[index].hasPrefix("```") {
                    code.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                segments.append(.code(
                    language: language,
                    code: code.joined(separator: "\n")
                ))
            } else {
                prose.append(line)
                index += 1
            }
        }

        flushProse()
        return segments
    }
}
