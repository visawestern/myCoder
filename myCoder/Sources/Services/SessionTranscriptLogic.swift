import Foundation

/// Builds a portable transcript for the sidebar's Share / Export actions.
/// Pure and stable so both can render identical content.
enum SessionTranscriptLogic {
    static func markdown(title: String, messages: [Message], exportedAt: Date = Date()) -> String {
        var lines: [String] = ["# \(title)", ""]
        let formatter = ISO8601DateFormatter()
        lines.append("_Exported from myCoder on \(formatter.string(from: exportedAt))_")
        lines.append("")

        for message in messages {
            let role: String
            switch message.role {
            case .user: role = "User"
            case .assistant: role = "Assistant"
            case .system: role = "System"
            }
            let body = bodyText(for: message)
            guard !body.isEmpty else { continue }
            lines.append("## \(role)")
            lines.append(body)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// Content plus tool interactions. Tool calls are part of what happened in
    /// the chat and must survive export even when `content` is empty.
    static func bodyText(for message: Message) -> String {
        var chunks: [String] = []
        let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !content.isEmpty { chunks.append(content) }

        for part in message.parts {
            switch part {
            case .toolCall(let name, let args, let result, _):
                var line = "`tool: \(name)`"
                if !args.isEmpty { line += " \(args)" }
                if let result, !result.isEmpty {
                    line += "\n```\n\(result)\n```"
                }
                chunks.append(line)
            case .image:
                chunks.append("[image]")
            case .text, .reasoning, .stepStart, .stepFinish, .routeInfo, .compiledContext:
                break
            }
        }
        return chunks.joined(separator: "\n\n")
    }

    /// Filesystem-safe file name for the export panel.
    static func fileName(title: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let cleaned = title.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { $0.append($1) }
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = cleaned.isEmpty ? "chat-transcript" : cleaned
        return "\(String(base.prefix(60))).md"
    }
}
