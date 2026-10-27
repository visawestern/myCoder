import Foundation

enum MessageType: String, CaseIterable, Identifiable {
    case build = "Build"
    case plan = "Plan"
    case compose = "Compose"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .build: return "hammer.fill"
        case .plan: return "text.book.closed"
        case .compose: return "square.and.pencil"
        }
    }
    
    init(from agentMode: AgentMode) {
        switch agentMode {
        case .build: self = .build
        case .plan: self = .plan
        case .compose: self = .compose
        }
    }
    
    var toAgentMode: AgentMode {
        switch self {
        case .build: return .build
        case .plan: return .plan
        case .compose: return .compose
        }
    }
}

enum MessageRole {
    case user
    case assistant
    case system
}

enum MessageAction: String {
    case wrote = "Wrote"
    case updated = "Updated"
    case ran = "Ran"
    case searched = "Searched"
    case explored = "Explored"
}

// MARK: - Plus Menu

enum PlusMenuItem: String, CaseIterable {
    case addAttachment
    case addPhoto
    case insertMention
    case insertCommand
    case insertSession
    
    var icon: String {
        switch self {
        case .addAttachment: return "paperclip"
        case .addPhoto: return "photo"
        case .insertMention: return "at"
        case .insertCommand: return "slash.forward"
        case .insertSession: return "number"
        }
    }
    
    var label: String {
        switch self {
        case .addAttachment: return "Add attachment"
        case .addPhoto: return "Add photo"
        case .insertMention: return "Insert @ mention"
        case .insertCommand: return "Insert / command"
        case .insertSession: return "Insert # session"
        }
    }
    
    var prefix: String? {
        switch self {
        case .insertMention: return "@"
        case .insertCommand: return "/"
        case .insertSession: return "#"
        case .addAttachment, .addPhoto: return nil
        }
    }
}

/// One tool call waiting for the user's verdict. Unlike the legacy single
/// web-agent approval fields on `Message`, this list keeps every call in a
/// multi-call response visible and independently resolvable. `callID` links
/// the card to the exact tool-call part so the card can be rendered directly
/// after that call in the chat.
struct PendingToolApproval: Identifiable, Equatable {
    let id: String
    let callID: String
    let tool: String
    let message: String
    let createdAt: Date
    /// Folder outside the project the user granted access to. Set when the
    /// approval is an out-of-project access request instead of a plain
    /// tool-approval prompt.
    let accessGrant: String?

    init(
        id: String = UUID().uuidString,
        callID: String,
        tool: String,
        message: String,
        createdAt: Date = Date(),
        accessGrant: String? = nil
    ) {
        self.id = id
        self.callID = callID
        self.tool = tool
        self.message = message
        self.createdAt = createdAt
        self.accessGrant = accessGrant
    }
}

struct Message: Identifiable {
    let id: String
    var serverID: String?  // Server-assigned ID for DB reconciliation
    let role: MessageRole
    var content: String
    let timestamp: Date
    var agentName: String?
    var toolCalls: [ToolCall]?
    var isStreaming: Bool
    var action: MessageAction?
    var files: [FileInfo]?
    var command: String?
    var tokensAdded: Int?
    var tokensRemoved: Int?
    var parts: [MessagePartContent]
    var reasoning: String
    /// Reasoning blocks in arrival order — every agent-loop iteration that
    /// produced thinking gets its own entry, so the chat renders one spoiler
    /// per block instead of one merged blob, and nothing is dropped.
    var reasoningSegments: [String]
    var isFinished: Bool
    var reasoningStartedAt: Date?
    var reasoningEndedAt: Date?
    var attachedImages: [ClipboardImage]?
    var usage: UsageCapture?
    // Pending tool-approval card (web agent): the driver is blocked waiting
    // for the user to Allow/Deny this request.
    var pendingApprovalID: String?
    var pendingApprovalTool: String?
    var pendingApprovalMessage: String?
    /// Queued inline approvals for direct local-model tool loops. Multiple
    /// calls can wait at once, across multiple chats.
    var pendingApprovals: [PendingToolApproval]

    /// Elapsed reasoning time. While reasoning is in progress (no end
    /// timestamp yet) this measures from start to now so a live UI can show
    /// a running count; once `reasoningEndedAt` is set the value freezes at
    /// the final duration instead of growing indefinitely.
    var reasoningDuration: TimeInterval? {
        guard let startedAt = reasoningStartedAt else { return nil }
        let end = reasoningEndedAt ?? Date()
        return end.timeIntervalSince(startedAt)
    }

    init(id: String = UUID().uuidString, serverID: String? = nil, role: MessageRole, content: String, agentName: String? = nil, toolCalls: [ToolCall]? = nil, isStreaming: Bool = false, action: MessageAction? = nil, files: [FileInfo]? = nil, command: String? = nil, tokensAdded: Int? = nil, tokensRemoved: Int? = nil, parts: [MessagePartContent] = [], reasoning: String = "", reasoningSegments: [String] = [], isFinished: Bool = false, reasoningStartedAt: Date? = nil, reasoningEndedAt: Date? = nil, attachedImages: [ClipboardImage]? = nil, usage: UsageCapture? = nil, pendingApprovalID: String? = nil, pendingApprovalTool: String? = nil, pendingApprovalMessage: String? = nil, pendingApprovals: [PendingToolApproval] = []) {
        self.id = id
        self.serverID = serverID
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.agentName = agentName
        self.toolCalls = toolCalls
        self.isStreaming = isStreaming
        self.action = action
        self.files = files
        self.command = command
        self.tokensAdded = tokensAdded
        self.tokensRemoved = tokensRemoved
        self.parts = parts
        self.reasoning = reasoning
        self.reasoningSegments = reasoningSegments
        self.isFinished = isFinished
        self.reasoningStartedAt = reasoningStartedAt
        self.reasoningEndedAt = reasoningEndedAt
        self.attachedImages = attachedImages
        self.usage = usage
        self.pendingApprovalID = pendingApprovalID
        self.pendingApprovalTool = pendingApprovalTool
        self.pendingApprovalMessage = pendingApprovalMessage
        self.pendingApprovals = pendingApprovals
    }
}

enum MessagePartContent: Identifiable {
    case text(String)
    case reasoning(String)
    case toolCall(name: String, args: String, result: String?, callID: String?)
    case stepStart
    case stepFinish
    case image(base64: String, mimeType: String)
    /// Route metadata chips (provider/local chat/remote chat/model/effort)
    /// shown in the message header — NOT part of the answer text
    /// (user directive 2026-09-08: the footer must not pollute the answer).
    case routeInfo(chips: [String])
    /// The full point context that was compiled locally and sent with this
    /// message (user directive D2: the button shows it in full, no summary).
    case compiledContext(String)

    var id: String {
        switch self {
        case .text(let t): return "text-\(t.hashValue)"
        case .reasoning(let r): return "reasoning-\(r.hashValue)"
        case .toolCall(let n, let a, _, let callID):
            if let callID, !callID.isEmpty { return "tool-\(callID)" }
            return "tool-\(n)-\(a.hashValue)"
        case .stepStart: return "step-start"
        case .stepFinish: return "step-finish"
        case .image(let b64, _): return "image-\(b64.hashValue)"
        case .routeInfo(let chips): return "route-\(chips.joined(separator: "|").hashValue)"
        case .compiledContext(let text): return "compiled-context-\(text.hashValue)"
        }
    }
}

struct FileInfo: Identifiable {
    let id = UUID()
    let name: String
    let type: FileType
    var path: String?

    init(name: String, type: FileType, path: String? = nil) {
        self.name = name
        self.type = type
        self.path = path
    }
}

enum FileType: String {
    case html = "HTML"
    case css = "CSS"
    case javascript = "JS"
    case typescript = "TS"
    case python = "PY"
    case swift = "SWIFT"
    case dart = "DART"
    case json = "JSON"
    case yaml = "YAML"
    case markdown = "MD"
    case unknown = "FILE"
    
    static func from(ext: String) -> FileType {
        switch ext.lowercased() {
        case "swift": return .swift
        case "py", "python": return .python
        case "js", "javascript": return .javascript
        case "ts", "typescript": return .typescript
        case "css": return .css
        case "html", "htm": return .html
        case "dart": return .dart
        case "json": return .json
        case "yaml", "yml": return .yaml
        case "md", "markdown": return .markdown
        default: return .unknown
        }
    }
    
    var color: String {
        switch self {
        case .html: return "FF6B6B"
        case .css: return "4ECDC4"
        case .javascript: return "FFD93D"
        case .typescript: return "3178C6"
        case .python: return "3776AB"
        case .swift: return "F05138"
        case .dart: return "0175C2"
        case .json: return "999999"
        case .yaml: return "CB171E"
        case .markdown: return "FFFFFF"
        case .unknown: return "999999"
        }
    }
}

struct ToolCall: Identifiable {
    let id = UUID()
    let name: String
    let arguments: String
    var result: String?
}
