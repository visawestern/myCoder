import Foundation

/// Posted by the top bar when the user picks one of the eight copy/save
/// variants; `userInfo["variant"]` carries `ChatExportVariant.rawValue`.
extension Notification.Name {
    static let exportChat = Notification.Name("MiMoExportChat")
}

/// The eight chat copy/export variants offered by the top-bar menu.
/// Copy variants 1–4, save variants 5–8 (the user's approved list).
enum ChatExportVariant: String, CaseIterable, Identifiable {
    case copyPlain
    case copyCalls
    case copyResults
    case copyFullJSON
    case saveText
    case saveMarkdown
    case saveJSON
    case saveHTML

    var id: String { rawValue }

    /// True when the variant writes to the pasteboard instead of a file.
    var isCopy: Bool {
        switch self {
        case .copyPlain, .copyCalls, .copyResults, .copyFullJSON: return true
        case .saveText, .saveMarkdown, .saveJSON, .saveHTML: return false
        }
    }

    /// File extension for save variants; nil for copy variants.
    var fileExtension: String? {
        switch self {
        case .copyPlain, .copyCalls, .copyResults, .copyFullJSON: return nil
        case .saveText: return "txt"
        case .saveMarkdown: return "md"
        case .saveJSON: return "json"
        case .saveHTML: return "html"
        }
    }

    /// Menu label. Uses the runtime localizer so the Russian UI is complete.
    var menuTitle: String {
        switch self {
        case .copyPlain: return L.t("Copy — text, no tool results")
        case .copyCalls: return L.t("Copy — text with tool calls, no results")
        case .copyResults: return L.t("Copy — text with tool results")
        case .copyFullJSON: return L.t("Copy — full JSON")
        case .saveText: return L.t("Save — text with results (.txt)")
        case .saveMarkdown: return L.t("Save — Markdown with results (.md)")
        case .saveJSON: return L.t("Save — JSON with results (.json)")
        case .saveHTML: return L.t("Save — HTML book with results (.html)")
        }
    }
}

/// Pure builders for every chat export variant.
///
/// `entries(from:)` normalizes messages through the same display pipeline the
/// chat uses, so hidden route chips and execution markers never leak into an
/// export. Everything below is deterministic and testable without a UI.
enum ChatExportLogic {

    struct ToolActivity: Equatable {
        let name: String
        let arguments: String
        let result: String?
    }

    struct MessageExport: Equatable {
        let role: String
        let text: String
        let tools: [ToolActivity]
    }

    /// Input: raw messages. Output: display messages with text + tool calls,
    /// empty entries dropped. Dependencies: MessageDisplayLogic +
    /// MessageContentSanitizerLogic.
    static func entries(from messages: [Message]) -> [MessageExport] {
        MessageDisplayLogic.messagesForDisplay(messages).compactMap { message in
            var textChunks: [String] = []
            var tools: [ToolActivity] = []
            for part in MessageDisplayLogic.chatDisplayParts(message.parts) {
                switch part {
                case .text(let value):
                    if let sanitized = MessageContentSanitizerLogic.sanitizedTextPart(value),
                       !sanitized.isEmpty {
                        textChunks.append(sanitized)
                    }
                case .toolCall(let name, let args, let result, _):
                    tools.append(ToolActivity(name: name, arguments: args, result: result))
                default:
                    break
                }
            }
            var text = textChunks.joined(separator: "\n\n")
            if text.isEmpty,
               let sanitized = MessageContentSanitizerLogic.sanitizedTextPart(message.content) {
                text = sanitized
            }
            guard !text.isEmpty || !tools.isEmpty else { return nil }
            let role: String
            switch message.role {
            case .user: role = "User"
            case .assistant: role = "Assistant"
            case .system: role = "System"
            }
            return MessageExport(role: role, text: text, tools: tools)
        }
    }

    static func hasContent(_ messages: [Message]) -> Bool {
        !entries(from: messages).isEmpty
    }

    /// Plain text. Variant 1 keeps the historical transcript byte-for-byte;
    /// richer variants add tool calls and optionally their results.
    static func plainText(messages: [Message],
                          includeCalls: Bool,
                          includeResults: Bool) -> String {
        guard includeCalls else { return ChatCopyLogic.transcript(from: messages) }
        return entries(from: messages).compactMap { entry -> String? in
            var blocks: [String] = []
            if !entry.text.isEmpty {
                blocks.append("\(entry.role):\n\(entry.text)")
            }
            for tool in entry.tools {
                var block = "Tool call: \(tool.name)\nArguments: \(tool.arguments)"
                if includeResults, let result = tool.result, !result.isEmpty {
                    block += "\nResult:\n\(result)"
                }
                blocks.append(block)
            }
            return blocks.isEmpty ? nil : blocks.joined(separator: "\n\n")
        }
        .joined(separator: "\n\n---\n\n")
    }

    /// Markdown with roles, tool calls and results.
    static func markdown(messages: [Message], title: String,
                         exportedAt: Date = Date()) -> String {
        var lines = ["# \(title)", ""]
        lines.append("_Exported from myCoder on \(iso(exportedAt))_")
        lines.append("")
        for entry in entries(from: messages) {
            lines.append("## \(entry.role)")
            if !entry.text.isEmpty {
                lines.append("")
                lines.append(entry.text)
            }
            for tool in entry.tools {
                lines.append("")
                lines.append("### Tool call: \(tool.name)")
                lines.append("```json")
                lines.append(tool.arguments)
                lines.append("```")
                if let result = tool.result, !result.isEmpty {
                    lines.append("")
                    lines.append("**Result**")
                    lines.append("```")
                    lines.append(result)
                    lines.append("```")
                }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// JSON export. `full` keeps every message field and part (including
    /// reasoning and image bytes); otherwise a compact role/text/tool document
    /// with results is produced.
    static func json(messages: [Message], title: String,
                     exportedAt: Date = Date(), full: Bool) -> String {
        let root: [String: Any]
        if full {
            root = [
                "title": title,
                "exportedAt": iso(exportedAt),
                "messages": messages.map(fullMessage)
            ]
        } else {
            root = [
                "title": title,
                "exportedAt": iso(exportedAt),
                "messages": entries(from: messages).map { entry -> [String: Any] in
                    var dict: [String: Any] = ["role": entry.role, "text": entry.text]
                    if !entry.tools.isEmpty {
                        dict["toolCalls"] = entry.tools.map { tool -> [String: Any] in
                            var call: [String: Any] = [
                                "name": tool.name,
                                "arguments": tool.arguments
                            ]
                            if let result = tool.result {
                                call["result"] = result
                            }
                            return call
                        }
                    }
                    return dict
                }
            ]
        }
        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys]
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: options) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Safe default file name for a save variant.
    /// Input: chat title + variant. Output: a name without path separators,
    /// with the variant's extension. Dependencies: none.
    static func fileName(title: String, variant: ChatExportVariant) -> String {
        let extensionName = variant.fileExtension ?? "txt"
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        let cleaned = title
            .components(separatedBy: forbidden)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = cleaned
            .split(separator: " ")
            .joined(separator: " ")
        let base = collapsed.isEmpty ? "chat" : String(collapsed.prefix(80))
        return "\(base).\(extensionName)"
    }

    /// The content for a variant, or nil when the chat has nothing to export.
    /// HTML is delegated to `ChatHTMLBook`.
    static func content(for variant: ChatExportVariant, messages: [Message],
                        title: String, exportedAt: Date = Date()) -> String? {
        guard hasContent(messages) else { return nil }
        switch variant {
        case .copyPlain, .saveText:
            return plainText(messages: messages, includeCalls: false, includeResults: false)
        case .copyCalls:
            return plainText(messages: messages, includeCalls: true, includeResults: false)
        case .copyResults:
            return plainText(messages: messages, includeCalls: true, includeResults: true)
        case .copyFullJSON:
            return json(messages: messages, title: title, exportedAt: exportedAt, full: true)
        case .saveMarkdown:
            return markdown(messages: messages, title: title, exportedAt: exportedAt)
        case .saveJSON:
            return json(messages: messages, title: title, exportedAt: exportedAt, full: false)
        case .saveHTML:
            return ChatHTMLBook.render(messages: messages, title: title, exportedAt: exportedAt)
        }
    }

    // MARK: - Full JSON

    private static func fullMessage(_ message: Message) -> [String: Any] {
        var dict: [String: Any] = [
            "id": message.id,
            "role": roleName(message.role),
            "content": message.content,
            "timestamp": iso(message.timestamp),
            "isFinished": message.isFinished,
            "reasoning": message.reasoning,
            "reasoningSegments": message.reasoningSegments,
            "parts": message.parts.map(fullPart)
        ]
        if let agentName = message.agentName { dict["agentName"] = agentName }
        if let command = message.command { dict["command"] = command }
        if let summary = message.contextSummary { dict["contextSummary"] = summary }
        return dict
    }

    private static func fullPart(_ part: MessagePartContent) -> [String: Any] {
        switch part {
        case .text(let text):
            return ["type": "text", "text": text]
        case .reasoning(let text):
            return ["type": "reasoning", "text": text]
        case .toolCall(let name, let args, let result, let callID):
            var dict: [String: Any] = ["type": "tool_call", "name": name, "args": args]
            if let result { dict["result"] = result }
            if let callID { dict["callID"] = callID }
            return dict
        case .stepStart:
            return ["type": "step_start"]
        case .stepFinish:
            return ["type": "step_finish"]
        case .image(let base64, let mimeType):
            return ["type": "image", "mimeType": mimeType, "base64": base64]
        case .routeInfo(let chips):
            return ["type": "route_info", "chips": chips]
        case .compiledContext(let text):
            return ["type": "compiled_context", "text": text]
        }
    }

    private static func roleName(_ role: MessageRole) -> String {
        switch role {
        case .user: return "user"
        case .assistant: return "assistant"
        case .system: return "system"
        }
    }

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
