import Foundation

// MARK: - Health Response

struct MimoHealthResponse: Codable, Sendable {
    let healthy: Bool
    let version: String
}

// MARK: - Project Response

struct MimoProjectResponse: Codable, Sendable {
    let id: String
    let worktree: String
    let time: MimoTimeRange
    let sandboxes: [MimoSandbox]
}

struct MimoTimeRange: Codable, Sendable {
    let created: Int64
    let updated: Int64
}

struct MimoSandbox: Codable, Sendable {
    let id: String?
    let name: String?
}

// MARK: - Session Response

struct MimoSessionResponse: Codable, Sendable {
    let id: String
    let slug: String
    let projectID: String
    let directory: String
    let title: String
    let version: String
    let summary: MimoSessionSummary?
    let time: MimoTimeRange
    let project: MimoProjectRef?
    let parentID: String?
}

struct MimoSessionSummary: Codable, Sendable {
    let additions: Int
    let deletions: Int
    let files: Int
}

struct MimoProjectRef: Codable, Sendable {
    let id: String
    let worktree: String
}

// MARK: - Session Status

struct MimoSessionStatusResponse: Codable, Sendable {
    let id: String
    let status: String
    let title: String?
    let time: MimoTimeRange?
}

// MARK: - Provider Response

struct MimoProvidersWrapper: Codable, Sendable {
    let providers: [MimoProviderResponse]
}

struct MimoProviderResponse: Codable, Sendable {
    let id: String
    let name: String
    let models: [String: MimoProviderModel]
}

struct MimoProviderModel: Codable, Sendable {
    let id: String
    let name: String?
    let status: String?
    let providerID: String?
    let capabilities: MimoModelCapabilities?
    let variants: [String: MimoModelVariant]?
    let limit: MimoModelLimit?
    let cost: MimoModelCost?

    init(
        id: String,
        name: String? = nil,
        status: String? = nil,
        providerID: String? = nil,
        capabilities: MimoModelCapabilities? = nil,
        variants: [String: MimoModelVariant]? = nil,
        limit: MimoModelLimit? = nil,
        cost: MimoModelCost? = nil
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.providerID = providerID
        self.capabilities = capabilities
        self.variants = variants
        self.limit = limit
        self.cost = cost
    }
}

struct MimoModelLimit: Codable, Sendable {
    let context: Int?
    let output: Int?
}

struct MimoModelCost: Codable, Sendable {
    let input: Double?
    let output: Double?
}

struct MimoModelCapabilities: Codable, Sendable, Equatable {
    let reasoning: Bool?
    let toolcall: Bool?
    let plan: Bool?
    let vision: Bool?
    let imagegen: Bool?

    init(
        reasoning: Bool? = nil,
        toolcall: Bool? = nil,
        plan: Bool? = nil,
        vision: Bool? = nil,
        imagegen: Bool? = nil
    ) {
        self.reasoning = reasoning
        self.toolcall = toolcall
        self.plan = plan
        self.vision = vision
        self.imagegen = imagegen
    }
}

struct MimoModelVariant: Codable, Sendable {
    let reasoningEffort: String?
}

// MARK: - File Response

struct MimoFileContentResponse: Codable, Sendable {
    let path: String
    let content: String
    let size: Int64?
}

struct MimoFileStatusResponse: Codable, Sendable {
    let path: String
    let status: String
    let additions: Int?
    let deletions: Int?
}

// MARK: - VCS Response

struct MimoVcsDiffResponse: Codable, Sendable {
    let files: [MimoVcsFileDiff]

    init(files: [MimoVcsFileDiff]) {
        self.files = files
    }

    init(from decoder: Decoder) throws {
        if var unkeyed = try? decoder.unkeyedContainer() {
            var items: [MimoVcsFileDiff] = []
            while !unkeyed.isAtEnd {
                items.append(try unkeyed.decode(MimoVcsFileDiff.self))
            }
            self.files = items
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.files = try container.decode([MimoVcsFileDiff].self, forKey: .files)
    }

    private enum CodingKeys: String, CodingKey {
        case files
    }
}

struct MimoVcsFileDiff: Codable, Sendable, Equatable {
    let path: String
    let status: String
    let additions: Int
    let deletions: Int

    init(path: String, status: String, additions: Int, deletions: Int) {
        self.path = path
        self.status = status
        self.additions = additions
        self.deletions = deletions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let path = try container.decodeIfPresent(String.self, forKey: .path) {
            self.path = path
        } else {
            self.path = try container.decode(String.self, forKey: .file)
        }
        self.status = try container.decodeIfPresent(String.self, forKey: .status) ?? "modified"
        self.additions = try container.decodeIfPresent(Int.self, forKey: .additions) ?? 0
        self.deletions = try container.decodeIfPresent(Int.self, forKey: .deletions) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(status, forKey: .status)
        try container.encode(additions, forKey: .additions)
        try container.encode(deletions, forKey: .deletions)
    }

    private enum CodingKeys: String, CodingKey {
        case path, file, status, additions, deletions
    }
}

// MARK: - Session

struct MimoSessionCreateResponse: Decodable {
    let id: String
    let slug: String
    let projectID: String
    let directory: String
    let title: String
}

// MARK: - Message

struct MimoMessageResponse: Decodable {
    let info: MimoMessageInfo?
    let parts: [MimoMessagePart]?
    
    var textContent: String {
        parts?.compactMap { part -> String? in
            if case .text(let text) = part { return text }
            return nil
        }.joined(separator: "\n") ?? ""
    }
}

struct MimoMessageInfo: Decodable {
    let id: String?
    let role: String?
    let agent: String?
    let modelID: String?
    let providerID: String?
    let variant: String?
    let model: MimoMessageModelRef?
}

struct MimoMessageModelRef: Decodable {
    let modelID: String?
    let providerID: String?
    let variant: String?
}

enum MimoMessagePart: Decodable {
    case text(String)
    case reasoning(String)
    case stepStart
    case stepFinish
    case toolInvocation(toolName: String, input: String?, result: String?, callID: String?)
    case image(mediaType: String, data: String)
    case other
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "text":
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        case "reasoning":
            let text = try container.decode(String.self, forKey: .text)
            self = .reasoning(text)
        case "step-start":
            self = .stepStart
        case "step-finish":
            self = .stepFinish
        case "tool-invocation", "tool-call":
            let toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
                ?? container.decodeIfPresent(String.self, forKey: .name)
                ?? container.decodeIfPresent(String.self, forKey: .tool)
                ?? "tool"
            let input = try container.decodeIfPresent(String.self, forKey: .input)
                ?? container.decodeIfPresent(String.self, forKey: .arguments)
            let result = try container.decodeIfPresent(String.self, forKey: .result)
            let callID = try container.decodeIfPresent(String.self, forKey: .callID)
                ?? container.decodeIfPresent(String.self, forKey: .id)
            self = .toolInvocation(toolName: toolName, input: input, result: result, callID: callID)
        case "tool":
            let toolName = try container.decodeIfPresent(String.self, forKey: .tool) ?? "tool"
            let callID = try container.decodeIfPresent(String.self, forKey: .callID)
                ?? container.decodeIfPresent(String.self, forKey: .id)
            if let stateValue = try? container.decode(JSONValue.self, forKey: .state),
               case .object(let stateObject) = stateValue {
                let stateMap = stateObject.mapValues { $0.foundationValue }
                let status = stateMap["status"] as? String
                let inputJSON = Self.inputJSON(from: stateMap["input"]) ?? "{}"
                let output = OpenCodeToolStatusLogic.extractOutput(from: stateMap)
                let pending = OpenCodeToolStatusLogic.isPending(status: status, output: output)
                self = .toolInvocation(
                    toolName: toolName,
                    input: inputJSON,
                    result: pending ? nil : output,
                    callID: callID
                )
            } else {
                let input = try container.decodeIfPresent(String.self, forKey: .input)
                self = .toolInvocation(toolName: toolName, input: input, result: nil, callID: callID)
            }
        case "image":
            let mediaType = try container.decodeIfPresent(String.self, forKey: .mediaType) ?? "image/png"
            let data = try container.decode(String.self, forKey: .data)
            self = .image(mediaType: mediaType, data: data)
        case "file":
            let mime = try container.decodeIfPresent(String.self, forKey: .mime)
                ?? container.decodeIfPresent(String.self, forKey: .mediaType)
                ?? "application/octet-stream"
            if let url = try container.decodeIfPresent(String.self, forKey: .url),
               MessagePartsBuilder.isImageMimeType(mime),
               let decoded = MessagePartsBuilder.base64FromDataURL(url) {
                self = .image(mediaType: decoded.mimeType, data: decoded.base64)
            } else if let data = try container.decodeIfPresent(String.self, forKey: .data),
                      MessagePartsBuilder.isImageMimeType(mime),
                      !data.isEmpty {
                self = .image(mediaType: mime, data: data)
            } else {
                self = .other
            }
        default:
            self = .other
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case type, text, toolName, name, tool, input, arguments, mediaType, mime, data, url, state, callID, id, result
    }

    private struct ToolPartState: Decodable {
        let status: String?
        let input: ToolPartInput?

        enum CodingKeys: String, CodingKey {
            case status, input
        }
    }

    private struct ToolPartInput: Decodable {
        let questions: [ToolPartQuestion]?
    }

    private struct ToolPartQuestion: Decodable {
        let header: String?
        let question: String?
        let prompt: String?
        let multiple: Bool?
        let multiSelect: Bool?
        let options: [ToolPartOption]?
    }

    private struct ToolPartOption: Decodable {
        let label: String?
        let title: String?
        let description: String?
    }

    private static func encodeToolInput(_ input: ToolPartInput?) -> String? {
        guard let input else { return nil }
        guard let questions = input.questions else { return "{}" }
        let rawQuestions: [[String: Any]] = questions.map { question in
            var dict: [String: Any] = [:]
            if let header = question.header { dict["header"] = header }
            if let prompt = question.question ?? question.prompt { dict["question"] = prompt }
            if let multiple = question.multiple ?? question.multiSelect { dict["multiple"] = multiple }
            if let options = question.options {
                dict["options"] = options.map { option in
                    var optionDict: [String: Any] = [:]
                    if let label = option.label ?? option.title { optionDict["label"] = label }
                    if let description = option.description { optionDict["description"] = description }
                    return optionDict
                }
            }
            return dict
        }
        guard JSONSerialization.isValidJSONObject(["questions": rawQuestions]),
              let data = try? JSONSerialization.data(withJSONObject: ["questions": rawQuestions]),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    private static func inputJSON(from value: Any?) -> String? {
        guard let value else { return nil }
        if let string = value as? String { return string }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return nil
    }

    private enum JSONValue: Decodable {
        case string(String)
        case number(Double)
        case bool(Bool)
        case object([String: JSONValue])
        case array([JSONValue])
        case null

        var foundationValue: Any {
            switch self {
            case .string(let value): return value
            case .number(let value): return value
            case .bool(let value): return value
            case .object(let value): return value.mapValues { $0.foundationValue }
            case .array(let value): return value.map(\.foundationValue)
            case .null: return NSNull()
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .null
            } else if let value = try? container.decode(Bool.self) {
                self = .bool(value)
            } else if let value = try? container.decode(Double.self) {
                self = .number(value)
            } else if let value = try? container.decode(String.self) {
                self = .string(value)
            } else if let value = try? container.decode([String: JSONValue].self) {
                self = .object(value)
            } else if let value = try? container.decode([JSONValue].self) {
                self = .array(value)
            } else {
                self = .null
            }
        }
    }
}

// MARK: - Sync Request (legacy)

struct SyncStartRequest: Codable {
    let prompt: String
    var files: [String]? = nil
}

// MARK: - Sync Response (legacy)

struct SyncStartResponse: Decodable {
    let session: MimoSessionResponse?
    let success: Bool
    
    init(success: Bool) {
        self.session = nil
        self.success = success
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        if let session = try container.decodeIfPresent(MimoSessionResponse.self, forKey: .session) {
            self.session = session
            self.success = true
        } else if let id = try container.decodeIfPresent(String.self, forKey: .id) {
            let title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
            let slug = try container.decodeIfPresent(String.self, forKey: .slug) ?? ""
            let projectID = try container.decodeIfPresent(String.self, forKey: .projectID) ?? ""
            let directory = try container.decodeIfPresent(String.self, forKey: .directory) ?? ""
            let version = try container.decodeIfPresent(String.self, forKey: .version) ?? "1.0"
            let time = try container.decodeIfPresent(MimoTimeRange.self, forKey: .time) ?? MimoTimeRange(created: 0, updated: 0)
            let summary = try container.decodeIfPresent(MimoSessionSummary.self, forKey: .summary)
            let project = try container.decodeIfPresent(MimoProjectRef.self, forKey: .project)
            let parentID = try container.decodeIfPresent(String.self, forKey: .parentID)
            
            self.session = MimoSessionResponse(
                id: id, slug: slug, projectID: projectID, directory: directory,
                title: title, version: version, summary: summary, time: time,
                project: project, parentID: parentID
            )
            self.success = true
        } else {
            self.session = nil
            self.success = true
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case session, id, title, slug, projectID, directory, version, time, summary, project, parentID
    }
}

// MARK: - Config Response

struct MimoConfigResponse: Codable, Sendable {
    let providers: [MimoProviderResponse]?
    let model: String?
    let theme: String?
    let permission: MimoPermissionConfig?
}

struct MimoPermissionConfig: Codable, Sendable, Equatable {
    let edit: String?
    let bash: String?
    let webfetch: String?
    let external_directory: String?

    var asDictionary: [String: String] {
        var dict: [String: String] = [:]
        if let edit { dict["edit"] = edit }
        if let bash { dict["bash"] = bash }
        if let webfetch { dict["webfetch"] = webfetch }
        if let external_directory { dict["external_directory"] = external_directory }
        return dict
    }
}

// MARK: - Mapping Extensions

extension MimoSessionResponse {
    func toChatSession() -> ChatSession {
        ChatSession(
            id: id,
            title: title,
            createdAt: Date(timeIntervalSince1970: TimeInterval(time.created)),
            updatedAt: Date(timeIntervalSince1970: TimeInterval(time.updated)),
            directory: directory,
            branch: nil,
            gitSummary: summary
        )
    }

    func toProject() -> Project {
        let name = (directory as NSString).lastPathComponent
        return Project(id: id, name: name, path: directory)
    }
}
