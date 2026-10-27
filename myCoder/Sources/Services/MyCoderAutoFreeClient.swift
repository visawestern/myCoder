import Foundation

/// Distinguishes between content, reasoning and native tool-call chunks from
/// the streaming response.
enum StreamEvent: Equatable {
    case content(String)
    case reasoning(String)
    case toolCall(id: String, name: String, arguments: String)

    var text: String {
        switch self {
        case .content(let s): return s
        case .reasoning(let s): return s
        case .toolCall: return ""
        }
    }
}

/// Anonymous OpenCode Zen client for myCoder Auto Free.
/// Eligible models are the trusted temporary free-model IDs plus any live
/// `-free`-suffixed route; paid catalog models are never selected automatically.
final class MyCoderAutoFreeClient {
    static let shared = MyCoderAutoFreeClient()

    static let providerBaseURL = URL(string: "https://opencode.ai/zen/v1")!
    static let defaultModelID = "big-pickle"
    static let maxConsecutiveFailures = 5

    /// Ordered by preference. The list is intersected with the live `/models`
    /// response so a retired free model can never be selected accidentally.
    /// Kept in sync with the live catalog (verified 2026-09-04: 8 `-free`
    /// routes live; `hy3-free` and `ling-3.0-tiny-free` retired by the server).
    static let freeModelIDs = [
        "big-pickle",
        "muse-spark-1.3-contributor-free",
        "deepseek-v4-flash-free",
        "mimo-v2.5-free",
        "muse-spark-1.2-contributor-free",
        "ling-3.0-flash-fin-free",
        "laguna-s-2.1-free",
        "nemotron-3-ultra-free",
        "nemotron-3.5-lightning-free"
    ]

    static let maximumErrorBodyBytes = 16_384

    private let session: URLSession
    private let baseURL: URL
    private let sessionDefaults: UserDefaults
    private let usesInjectedSession: Bool

    init(
        session: URLSession = .shared,
        baseURL: URL = MyCoderAutoFreeClient.providerBaseURL,
        sessionDefaults: UserDefaults = .standard
    ) {
        self.session = session
        self.baseURL = baseURL
        self.sessionDefaults = sessionDefaults
        self.usesInjectedSession = session !== URLSession.shared
    }

    struct ModelProfile: Identifiable, Hashable {
        let id: String
        let displayName: String
        let summary: String
        let capabilities: [String]

        var capabilityLine: String { capabilities.joined(separator: " · ") }
    }

    struct Model: Identifiable, Codable, Hashable {
        let id: String
        var name: String { MyCoderAutoFreeClient.profile(for: id).displayName }
        let isFree: Bool
        let contextLength: Int?
        let description: String?

        var profile: ModelProfile { MyCoderAutoFreeClient.profile(for: id) }
        var effectiveDescription: String { description ?? profile.summary }
        var contextDescription: String {
            if let contextLength { return "\(contextLength.formatted()) tokens" }
            return "Not reported by live catalog"
        }

        init(id: String, isFree: Bool = true, contextLength: Int? = nil, description: String? = nil) {
            self.id = id
            self.isFree = isFree
            self.contextLength = contextLength
            self.description = description
        }
    }

    static func profile(for modelID: String) -> ModelProfile {
        profiles[modelID] ?? ModelProfile(
            id: modelID,
            displayName: modelID,
            summary: "Temporary OpenCode free route.",
            capabilities: ["Free", "Anonymous", "SSE"]
        )
    }

    private static let profiles: [String: ModelProfile] = [
        "big-pickle": ModelProfile(
            id: "big-pickle",
            displayName: "Big Pickle",
            summary: "Preferred temporary OpenCode free route.",
            capabilities: ["Free", "Anonymous", "SSE"]
        ),
        "deepseek-v4-flash-free": ModelProfile(
            id: "deepseek-v4-flash-free",
            displayName: "DeepSeek V4 Flash Free",
            summary: "Temporary OpenCode free route.",
            capabilities: ["Free", "Anonymous", "SSE"]
        ),
        "mimo-v2.5-free": ModelProfile(
            id: "mimo-v2.5-free",
            displayName: "MiMo V2.5 Free",
            summary: "Temporary OpenCode free route.",
            capabilities: ["Free", "Anonymous", "SSE"]
        ),
        "muse-spark-1.3-contributor-free": ModelProfile(
            id: "muse-spark-1.3-contributor-free",
            displayName: "Muse Spark 1.3 Contributor Free",
            summary: "Temporary OpenCode free route.",
            capabilities: ["Free", "Anonymous", "SSE"]
        ),
        "muse-spark-1.2-contributor-free": ModelProfile(
            id: "muse-spark-1.2-contributor-free",
            displayName: "Muse Spark 1.2 Contributor Free",
            summary: "Temporary OpenCode free route.",
            capabilities: ["Free", "Anonymous", "SSE"]
        ),
        "ling-3.0-flash-fin-free": ModelProfile(
            id: "ling-3.0-flash-fin-free",
            displayName: "Ling 3.0 Flash Fin Free",
            summary: "Temporary OpenCode free route.",
            capabilities: ["Free", "Anonymous", "SSE"]
        ),
        "hy3-free": ModelProfile(
            id: "hy3-free",
            displayName: "Hy3 Free",
            summary: "Temporary OpenCode free route.",
            capabilities: ["Free", "Anonymous", "SSE"]
        ),
        "laguna-s-2.1-free": ModelProfile(
            id: "laguna-s-2.1-free",
            displayName: "Laguna S 2.1 Free",
            summary: "Temporary OpenCode free route.",
            capabilities: ["Free", "Anonymous", "SSE"]
        ),
        "ling-3.0-tiny-free": ModelProfile(
            id: "ling-3.0-tiny-free",
            displayName: "Ling 3.0 Tiny Free",
            summary: "Temporary OpenCode free route.",
            capabilities: ["Free", "Anonymous", "SSE"]
        ),
        "nemotron-3-ultra-free": ModelProfile(
            id: "nemotron-3-ultra-free",
            displayName: "Nemotron 3 Ultra Free",
            summary: "Temporary OpenCode free route.",
            capabilities: ["Free", "Anonymous", "SSE"]
        ),
        "nemotron-3.5-lightning-free": ModelProfile(
            id: "nemotron-3.5-lightning-free",
            displayName: "Nemotron 3.5 Lightning Free",
            summary: "Temporary OpenCode free route.",
            capabilities: ["Free", "Anonymous", "SSE"]
        )
    ]

    struct Message: Codable, Equatable {
        let role: String
        let content: Content
        var toolCalls: [ToolCall]?
        var toolCallID: String?

        enum CodingKeys: String, CodingKey {
            case role, content
            case toolCalls = "tool_calls"
            case toolCallID = "tool_call_id"
        }

        struct ToolCall: Codable, Equatable {
            let id: String
            let type: String
            let function: Function

            struct Function: Codable, Equatable {
                let name: String
                let arguments: String
            }
        }

        enum Content: Codable, Equatable {
            case text(String)
            case parts([MyCoderAutoFreeContentPart])

            init(from decoder: Decoder) throws {
                if let single = try? decoder.singleValueContainer(),
                   let text = try? single.decode(String.self) {
                    self = .text(text)
                    return
                }
                self = .parts(try [MyCoderAutoFreeContentPart](from: decoder))
            }

            func encode(to encoder: Encoder) throws {
                switch self {
                case .text(let text):
                    var single = encoder.singleValueContainer()
                    try single.encode(text)
                case .parts(let parts):
                    var container = encoder.unkeyedContainer()
                    for part in parts {
                        try container.encode(part)
                    }
                }
            }
        }

        init(role: String, content: String) {
            self.role = role
            self.content = .text(content)
            self.toolCalls = nil
            self.toolCallID = nil
        }

        init(role: String, parts: [MyCoderAutoFreeContentPart]) {
            self.role = role
            self.content = .parts(parts)
            self.toolCalls = nil
            self.toolCallID = nil
        }

        init(role: String, content: String, toolCalls: [ToolCall]? = nil, toolCallID: String? = nil) {
            self.role = role
            self.content = .text(content)
            self.toolCalls = toolCalls
            self.toolCallID = toolCallID
        }

        var textContent: String {
            switch content {
            case .text(let text):
                return text
            case .parts(let parts):
                return parts.compactMap { part -> String? in
                    if case .text(let value) = part { return value }
                    return nil
                }.joined(separator: "\n")
            }
        }

        var containsEnvironmentBlock: Bool {
            textContent.contains("<env>") && textContent.contains("Working directory:")
        }
    }

    /// Fetch the anonymous live catalog and return eligible free models:
    /// trusted IDs first (preference order), then any other live `-free` route.
    func listModels(context: OpenCodeRequestContext = .generated()) async throws -> [Model] {
        var request = URLRequest(url: baseURL.appendingPathComponent("models"))
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        context.applying(to: &request)

        let (data, response) = try await session.data(for: request)
        try validate(response, data: data, operation: "OpenCode free model list")
        let decoded = try JSONDecoder().decode(ModelListResponse.self, from: data)
        let byID = Dictionary(uniqueKeysWithValues: decoded.data.map { ($0.id, $0) })
        let liveFreeIDs = decoded.data.map(\.id).filter { Self.isEligibleFreeModel($0) }
        let orderedIDs = Self.freeModelIDs + liveFreeIDs.filter { !Self.freeModelIDs.contains($0) }.sorted()
        let models = orderedIDs.compactMap { id -> Model? in
            guard let dto = byID[id] else { return nil }
            return Model(id: dto.id, contextLength: dto.contextLength, description: dto.description)
        }
        guard !models.isEmpty else {
            throw MyCoderAutoFreeError.noFreeModels
        }
        return models
    }

    /// A model is eligible when it is a trusted temporary free route OR any
    /// live `-free`-suffixed route. The suffix is OpenCode Zen's own marker for
    /// free routes, so newly published free models (e.g. a future
    /// `*-contributor-free`) appear after refresh without an app update, while
    /// paid models (never `-free`-suffixed) stay unreachable anonymously.
    static func isEligibleFreeModel(_ modelID: String) -> Bool {
        freeModelIDs.contains(modelID) || modelID.hasSuffix("-free")
    }

    /// System preamble that teaches the model to proactively use the attached
    /// tools instead of just describing what it *would* do.  Without this,
    /// free models tend to explain steps instead of actually calling tools.
    static func toolUsagePreamble(projectRoot: String = "", isGitRepo: Bool = false) -> String {
        var lines: [String] = []
        lines.append("You are myCoder, a local coding agent with direct access to the user's project files and shell.")
        lines.append("You have tools attached. USE THEM PROACTIVELY — do not just describe what you would do.")
        lines.append("")
        lines.append("CRITICAL: You MUST invoke tools by emitting a tool-call block. Reply with ONE of")
        lines.append("these two exact forms and then WAIT for the tool result before continuing:")
        lines.append("")
        lines.append("Form A (JSON fenced block):")
        lines.append("```tool")
        lines.append(#"{"name": "<tool_name>", "args": { ... }}"#)
        lines.append("```")
        lines.append("")
        lines.append("Form B (XML tags — tool name directly after <tool_call>, no wrapper):")
        lines.append("<tool_call>read_file<arg_key>path</arg_key><arg_value>src/main.swift</arg_value></tool_call>")
        lines.append("")
        lines.append("Real example — list the project root then find the task file:")
        lines.append("<tool_call>list_dir<arg_key>path</arg_key><arg_value>.</arg_value></tool_call>")
        lines.append("")
        lines.append("Wait for the ```tool_result block after every call, then continue from that result.")
        lines.append("When the task is done, reply normally WITHOUT a tool block.")
        lines.append("")
        lines.append("Your FIRST reply to any task that needs project access MUST be a tool call, not prose.")
        lines.append("If you catch yourself writing 'I don't have access' — you DO: call a tool instead of asking the user to upload anything.")
        lines.append("")
        lines.append("Rules:")
        lines.append("- When the user asks to read, check, search, or explore code — call the appropriate tool IMMEDIATELY.")
        lines.append("- When the user asks to write, edit, or fix code — use write_file or edit_file tools IMMEDIATELY.")
        lines.append("- When the user asks to run something — use run_command IMMEDIATELY.")
        lines.append("- Never describe a file's contents from memory; always read it with read_file first.")
        lines.append("- Never explain how you would fix something; actually fix it with edit_file or write_file.")
        lines.append("- Prefer dedicated tools over shell commands when a purpose-built tool exists; never pretend a tool ran without its result.")
        lines.append("")
        lines.append("Available tools:")
        lines.append("- read_file: Read a file's contents. args: {\"path\": \"<relative path>\"}")
        lines.append("- write_file: Create or overwrite a file. args: {\"path\": \"<relative path>\", \"content\": \"<file content>\"}")
        lines.append("- edit_file: Replace an exact substring in a file. args: {\"path\": \"<relative path>\", \"old\": \"<text>\", \"new\": \"<text>\"}")
        lines.append("- list_dir: List entries of a directory. args: {\"path\": \"<relative path>\"}")
        lines.append("- grep: Search files for a regex pattern. args: {\"pattern\": \"<regex>\", \"path\": \"<relative path>\"}")
        lines.append("- run_command: Run a shell command (requires approval at restricted access). args: {\"command\": \"<shell command>\"}")
        lines.append("- glob: Find files matching a glob pattern. args: {\"pattern\": \"<glob pattern>\", \"path\": \"<relative path>\"}")
        lines.append("- git_status: Show git status. args: {\"path\": \"<repo path>\"}")
        lines.append("- git_diff: Show git diff. args: {\"path\": \"<repo path>\", \"staged\": <bool>}")
        lines.append("- git_log: Show git commit history. args: {\"path\": \"<repo path>\", \"limit\": <int>}")
        lines.append("")
        if !projectRoot.isEmpty {
            lines.append("Working directory: \(projectRoot)")
            lines.append("Is directory a git repo: \(isGitRepo ? "yes" : "no")")
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            lines.append("Today's date: \(fmt.string(from: Date()))")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    struct ToolDefinition: Codable, Equatable {
        let type: String
        let function: Function

        struct Function: Codable, Equatable {
            let name: String
            let description: String
            let parameters: Parameters
        }

        struct Parameters: Codable, Equatable {
            let type: String
            let properties: [String: Property]
            let required: [String]
        }

        struct Property: Codable, Equatable {
            let type: String
            var description: String? = nil
            var properties: [String: Property]? = nil
            var items: Item? = nil
            var enumValues: [String]? = nil

            enum CodingKeys: String, CodingKey {
                case type, description, properties, items
                case enumValues = "enum"
            }
        }

        struct Item: Codable, Equatable {
            let type: String
            var description: String? = nil
            var properties: [String: Property]? = nil
            var enumValues: [String]? = nil

            enum CodingKeys: String, CodingKey {
                case type, description, properties
                case enumValues = "enum"
            }
        }
    }

    static func nativeToolName(for tool: WebEmulatedTool) -> String {
        switch tool {
        case .readFile: return "read"
        case .writeFile: return "write"
        case .editFile: return "edit"
        case .runCommand: return "bash"
        case .webFetch: return "webfetch"
        case .todoWrite: return "todowrite"
        default: return tool.rawValue
        }
    }

    static func gateToolDefinitions() -> [ToolDefinition] {
        [toolDefinition(for: .readFile)]
    }

    static func agentToolDefinitions() -> [ToolDefinition] {
        WebEmulatedTool.allCases.map { toolDefinition(for: $0) }
    }

    /// Build an OpenAI-compatible tool definition from the emulated tool set so
    /// free models receive full tool descriptions in every prompt.
    static func toolDefinition(for tool: WebEmulatedTool) -> ToolDefinition {
        var properties: [String: ToolDefinition.Property] = [:]
        var required: [String] = []
        switch tool {
        case .readFile:
            properties["path"] = .init(type: "string", description: "Relative file path")
            required = ["path"]
        case .writeFile:
            properties["path"] = .init(type: "string", description: "Relative file path")
            properties["content"] = .init(type: "string", description: "File content")
            required = ["path", "content"]
        case .editFile:
            properties["path"] = .init(type: "string", description: "Relative file path")
            properties["old"] = .init(type: "string", description: "Exact text to replace")
            properties["new"] = .init(type: "string", description: "Replacement text")
            required = ["path", "old", "new"]
        case .listDir:
            properties["path"] = .init(type: "string", description: "Relative directory path")
            required = ["path"]
        case .grep:
            properties["pattern"] = .init(type: "string", description: "Regex pattern")
            properties["path"] = .init(type: "string", description: "Relative path to search in")
            required = ["pattern"]
        case .runCommand:
            properties["command"] = .init(type: "string", description: "Shell command to execute")
            required = ["command"]
        case .gitStatus:
            properties["path"] = .init(type: "string", description: "Repository path")
            required = []
        case .gitDiff:
            properties["path"] = .init(type: "string", description: "Repository path")
            properties["staged"] = .init(type: "boolean", description: "Show staged changes")
            required = []
        case .gitLog:
            properties["path"] = .init(type: "string", description: "Repository path")
            properties["limit"] = .init(type: "integer", description: "Max commits to show")
            required = []
        case .gitBranch:
            properties["branch"] = .init(type: "string", description: "Branch name")
            properties["create"] = .init(type: "boolean", description: "Create if missing")
            required = []
        case .gitCheckout:
            properties["branch"] = .init(type: "string", description: "Branch to switch to")
            required = ["branch"]
        case .gitCommit:
            properties["message"] = .init(type: "string", description: "Commit message")
            properties["addAll"] = .init(type: "boolean", description: "Stage all changes")
            required = ["message"]
        case .gitPush:
            properties["remote"] = .init(type: "string", description: "Remote name")
            properties["branch"] = .init(type: "string", description: "Branch name")
            required = []
        case .gitPull:
            properties["remote"] = .init(type: "string", description: "Remote name")
            properties["branch"] = .init(type: "string", description: "Branch name")
            required = []
        case .glob:
            properties["pattern"] = .init(type: "string", description: "Glob pattern")
            properties["path"] = .init(type: "string", description: "Relative path")
            required = ["pattern"]
        case .codeSearch:
            properties["query"] = .init(type: "string", description: "Symbol name or code text to search")
            properties["limit"] = .init(type: "integer", description: "Max hits (default 8)")
            required = ["query"]
        case .readSymbol:
            properties["id"] = .init(type: "string", description: "Symbol id returned by code_search")
            properties["path"] = .init(type: "string", description: "File path (alternative to id)")
            properties["name"] = .init(type: "string", description: "Symbol name (with path)")
            properties["line"] = .init(type: "integer", description: "Optional declaration line hint")
            required = []
        case .todoRead:
            break
        case .todoWrite:
            properties["todos"] = .init(
                type: "array",
                items: .init(
                    type: "object",
                    properties: [
                        "id": .init(type: "string"),
                        "content": .init(type: "string"),
                        "status": .init(type: "string", enumValues: ["pending", "in_progress", "completed"])
                    ]
                )
            )
            required = ["todos"]
        case .task:
            properties["description"] = .init(type: "string", description: "Task description")
            properties["prompt"] = .init(type: "string", description: "Detailed prompt")
            properties["subagentType"] = .init(type: "string", description: "Agent type")
            required = ["description", "prompt"]
        case .webFetch:
            properties["url"] = .init(type: "string", description: "http(s) URL to fetch as text")
            properties["limit"] = .init(type: "integer", description: "Max chars to return")
            required = ["url"]
        case .skill:
            properties["name"] = .init(type: "string", description: "Installed skill id (omit to list skills)")
            required = []
        case .taskCreate:
            properties["content"] = .init(type: "string", description: "Task text")
            properties["status"] = .init(type: "string", enumValues: ["pending", "in_progress", "completed"])
            required = ["content"]
        case .taskList:
            break
        case .taskUpdate:
            properties["id"] = .init(type: "string", description: "Todo id from task_list")
            properties["content"] = .init(type: "string", description: "New text (optional)")
            properties["status"] = .init(type: "string", enumValues: ["pending", "in_progress", "completed"])
            required = ["id"]
        }
        return ToolDefinition(
            type: "function",
            function: .init(
                name: nativeToolName(for: tool),
                description: tool.description,
                parameters: .init(type: "object", properties: properties, required: required)
            )
        )
    }

    static func emulatedToolCall(name: String, arguments: String) -> WebToolCall? {
        let flattened = flattenedArguments(arguments)
        let canonical = WebToolProtocolEmulator.canonicalized(
            WebToolCall(name: name, arguments: flattened)
        )
        guard let tool = WebEmulatedTool(rawValue: canonical.name) else { return canonical }
        return WebToolCall(
            name: canonical.name,
            arguments: WebToolProtocolEmulator.normalizedArguments(for: tool, from: canonical.arguments)
        )
    }

    static func flattenedArguments(_ json: String) -> [String: String] {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        var result: [String: String] = [:]
        for (key, value) in object {
            result[key] = argumentText(value)
        }
        return result
    }

    private static func argumentText(_ value: Any) -> String {
        if let text = value as? String { return text }
        if let number = value as? NSNumber {
            if String(cString: number.objCType) == "c" {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        }
        if let data = try? JSONSerialization.data(withJSONObject: value),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return String(describing: value)
    }

    /// Stream a completion without an API key. The selected model must be in
    /// the live temporary free catalog; this prevents accidental paid usage.
    func chatCompletion(
        model: String = MyCoderAutoFreeClient.defaultModelID,
        messages: [Message],
        parameters: ModelCallParameters = ModelCallParameters(),
        context: OpenCodeRequestContext = .generated(),
        tools: [ToolDefinition] = MyCoderAutoFreeClient.gateToolDefinitions(),
        toolChoice: String? = "none",
        projectRoot: String = "",
        isGitRepo: Bool = false
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let effectiveModel = model.isEmpty ? MyCoderAutoFreeClient.defaultModelID : model
                    guard MyCoderAutoFreeClient.isEligibleFreeModel(effectiveModel) else {
                        throw MyCoderAutoFreeError.modelUnavailable(effectiveModel, "Model is not in the OpenCode temporary free catalog")
                    }

                    let completionBody = CompletionRequest(
                        model: effectiveModel,
                        messages: MyCoderAutoFreeClient.messagesWithEnvironment(
                            messages,
                            projectRoot: projectRoot,
                            isGitRepo: isGitRepo
                        ),
                        parameters: parameters,
                        tools: tools,
                        toolChoice: toolChoice
                    )
                    let body = try JSONEncoder().encode(completionBody)
                    let requestContext = context.requestID == nil
                        ? context.withRequestID(OpenCodeRequestContext.requestID())
                        : context
                    try await self.streamCompletion(
                        requestContext: requestContext,
                        body: body,
                        continuation: continuation
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func streamCompletion(
        requestContext: OpenCodeRequestContext,
        body: Data,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        var context = requestContext
        var rotated = false
        while true {
            do {
                try await self.performStream(requestContext: context, body: body, continuation: continuation)
                return
            } catch let limit as StreamRateLimit {
                guard !rotated,
                      let replacement = OpenCodeSessionIdentifierStore.shared.rotate(
                        identifier: context.sessionID,
                        defaults: sessionDefaults
                      ) else {
                    throw limit.underlying
                }
                rotated = true
                context = context
                    .withSessionID(replacement)
                    .withRequestID(OpenCodeRequestContext.requestID())
            }
        }
    }

    private func performStream(
        requestContext: OpenCodeRequestContext,
        body: Data,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        requestContext.applying(to: &request)
        request.httpBody = body

        if !usesInjectedSession, baseURL.host == Self.providerBaseURL.host, let bunPath = Self.bunExecutablePath() {
            try await performStreamViaBun(bunPath: bunPath, request: request, body: body, continuation: continuation)
            return
        }

        let (bytes, response) = try await session.bytes(for: request)
        let errorBody: Data
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            errorBody = try await Self.readErrorBody(bytes)
        } else {
            errorBody = Data()
        }
        do {
            try validate(response, data: errorBody, operation: "Free model streaming")
        } catch let error as MyCoderAutoFreeError {
            if case .rateLimited = error {
                throw StreamRateLimit(underlying: error)
            }
            throw error
        }
        let lineStream = AsyncThrowingStream<String, Error> { box in
            let forward = Task {
                do {
                    for try await line in bytes.lines {
                        box.yield(line)
                    }
                    box.finish()
                } catch {
                    box.finish(throwing: error)
                }
            }
            box.onTermination = { _ in forward.cancel() }
        }
        try await consumeSSE(lineStream, continuation: continuation)
    }

    private func performStreamViaBun(
        bunPath: String,
        request: URLRequest,
        body: Data,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        let headers = request.allHTTPHeaderFields ?? [:]
        let opened = try await BunHTTPTransport.open(
            url: request.url!,
            headers: headers,
            body: body,
            bunPath: bunPath
        )
        guard (200..<300).contains(opened.statusCode) else {
            let synthetic = HTTPURLResponse(
                url: request.url!,
                statusCode: opened.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            do {
                try validate(synthetic, data: opened.errorBody, operation: "Free model streaming")
            } catch let error as MyCoderAutoFreeError {
                if case .rateLimited = error {
                    throw StreamRateLimit(underlying: error)
                }
                throw error
            }
            throw MyCoderAutoFreeError.apiError("HTTP \(opened.statusCode)")
        }
        try await consumeSSE(opened.lines, continuation: continuation)
    }

    private func consumeSSE(
        _ lines: AsyncThrowingStream<String, Error>,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        var emitted = false
        var nativeToolCalls = NativeToolCallAccumulator()
        for try await line in lines {
            guard line.hasPrefix("data: ") else { continue }
            let json = String(line.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
            if json == "[DONE]" { break }
            // Error envelopes can arrive inside a successful SSE response.
            if let error = MyCoderAutoFreeError.streamError(in: json) {
                throw error
            }
            guard let data = json.data(using: .utf8) else { continue }
            if let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data) {
                if let content = chunk.choices.first?.delta.content, !content.isEmpty {
                    emitted = true
                    continuation.yield(.content(content))
                }
                if let reasoning = chunk.choices.first?.delta.reasoningContent, !reasoning.isEmpty {
                    emitted = true
                    continuation.yield(.reasoning(reasoning))
                }
                for delta in chunk.choices.first?.delta.toolCalls ?? [] {
                    nativeToolCalls.append(delta)
                }
            }
        }
        for call in nativeToolCalls.completedCalls {
            emitted = true
            continuation.yield(.toolCall(id: call.id, name: call.name, arguments: call.arguments))
        }
        guard emitted else { throw MyCoderAutoFreeError.emptyResponse }
        continuation.finish()
    }

    static func bunExecutablePath() -> String? {
        if ProcessInfo.processInfo.environment["MYCODER_BUN_TRANSPORT"] == "0" {
            return nil
        }
        var candidates: [String] = []
        if let install = ProcessInfo.processInfo.environment["BUN_INSTALL"], !install.isEmpty {
            candidates.append((install as NSString).appendingPathComponent("bin/bun"))
        }
        candidates.append(FileManager.default.homeDirectoryForCurrentUser.path + "/.bun/bin/bun")
        candidates.append(contentsOf: [
            "/usr/local/bin/bun",
            "/opt/homebrew/bin/bun",
            "/usr/bin/bun"
        ])
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// The upstream free tier serves a request only when a system message
    /// describes the environment in an `<env>` block; without it the request
    /// is answered with a free-usage limit instead of a model response.
    static func environmentBlock(projectRoot: String, isGitRepo: Bool) -> String {
        let workingDirectory = projectRoot.isEmpty
            ? FileManager.default.currentDirectoryPath
            : projectRoot
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d yyyy"
        return """
        Here is some useful information about the environment you are running in:
        <env>
          Working directory: \(workingDirectory)
          Workspace root folder: \(workingDirectory)
          Is directory a git repo: \(isGitRepo ? "yes" : "no")
          Platform: \(platformName)
          Today's date: \(formatter.string(from: Date()))
        </env>
        """
    }

    static var platformName: String {
        #if os(macOS)
        return "darwin"
        #elseif os(Linux)
        return "linux"
        #elseif os(Windows)
        return "win32"
        #else
        return "unknown"
        #endif
    }

    /// Add the environment block to the conversation when no system message
    /// carries one yet.
    static func messagesWithEnvironment(
        _ messages: [Message],
        projectRoot: String,
        isGitRepo: Bool
    ) -> [Message] {
        if messages.contains(where: { $0.role == "system" && $0.containsEnvironmentBlock }) {
            return messages
        }
        var result = messages
        result.insert(
            Message(role: "system", content: environmentBlock(projectRoot: projectRoot, isGitRepo: isGitRepo)),
            at: 0
        )
        return result
    }

    static func shouldSwitchImmediately(for error: Error) -> Bool {
        if let autoFreeError = error as? MyCoderAutoFreeError {
            switch autoFreeError {
            case .freeTierBlocked:
                return false
            case .rateLimited, .modelUnavailable:
                return true
            case .apiError(let message):
                let lower = message.lowercased()
                return lower.contains("429") || lower.contains("rate limit") || lower.contains("ratelimit") || lower.contains("model")
            case .noFreeModels, .emptyResponse:
                return false
            }
        }
        return false
    }

    /// A client-identity gate cannot be fixed by trying the next model —
    /// halt the carousel and surface one honest message instead.
    static func shouldHaltFailover(for error: Error) -> Bool {
        if let autoFreeError = error as? MyCoderAutoFreeError,
           case .freeTierBlocked = autoFreeError {
            return true
        }
        return false
    }

    static func shouldSwitch(for error: Error, consecutiveFailures: Int) -> Bool {
        if shouldHaltFailover(for: error) { return false }
        return consecutiveFailures >= maxConsecutiveFailures || shouldSwitchImmediately(for: error)
    }

    /// Error responses are not SSE streams; retain enough body for diagnosis
    /// without buffering an unbounded response before validating its status.
    static func readErrorBody<Bytes: AsyncSequence>(
        _ bytes: Bytes,
        maxBytes: Int = maximumErrorBodyBytes
    ) async throws -> Data where Bytes.Element == UInt8 {
        guard maxBytes > 0 else { return Data() }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count == maxBytes { break }
        }
        return data
    }

    private func validate(_ response: URLResponse, data: Data, operation: String) throws {
        guard let http = response as? HTTPURLResponse else {
            throw MyCoderAutoFreeError.apiError("Invalid response from free model server")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(decoding: data.prefix(Self.maximumErrorBodyBytes), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw MyCoderAutoFreeError.mapHttpError(statusCode: http.statusCode, body: body, operation: operation)
        }
    }
}

private struct StreamRateLimit: Error {
    let underlying: MyCoderAutoFreeError
}

private struct ModelListResponse: Decodable {
    let data: [ModelDTO]

    struct ModelDTO: Decodable {
        let id: String
        let contextLength: Int?
        let description: String?

        enum CodingKeys: String, CodingKey {
            case id
            case contextLength = "context_length"
            case description
        }
    }
}

private struct CompletionRequest: Encodable {
    let model: String
    let messages: [MyCoderAutoFreeClient.Message]
    let parameters: ModelCallParameters
    let tools: [MyCoderAutoFreeClient.ToolDefinition]
    let toolChoice: String?

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, temperature, maxTokens = "max_tokens", topP = "top_p", tools
        case toolChoice = "tool_choice"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encode(true, forKey: .stream)
        try container.encodeIfPresent(parameters.temperature, forKey: .temperature)
        try container.encodeIfPresent(parameters.maxTokens, forKey: .maxTokens)
        try container.encodeIfPresent(parameters.topP, forKey: .topP)
        if !tools.isEmpty {
            try container.encode(tools, forKey: .tools)
            try container.encodeIfPresent(toolChoice, forKey: .toolChoice)
        }
    }
}

private struct StreamChunk: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let delta: Delta

        struct Delta: Decodable {
            let content: String?
            let reasoningContent: String?
            let toolCalls: [ToolCallDelta]?

            enum CodingKeys: String, CodingKey {
                case content
                case reasoningContent = "reasoning_content"
                case toolCalls = "tool_calls"
            }
        }
    }
}

private struct ToolCallDelta: Decodable {
    let index: Int?
    let id: String?
    let type: String?
    let function: FunctionDelta?

    struct FunctionDelta: Decodable {
        let name: String?
        let arguments: String?
    }
}

private struct NativeToolCallAccumulator {
    private var order: [Int] = []
    private var calls: [Int: (id: String, name: String, arguments: String)] = [:]

    mutating func append(_ delta: ToolCallDelta) {
        let index = delta.index ?? 0
        var current = calls[index] ?? (id: "", name: "", arguments: "")
        if let id = delta.id, !id.isEmpty { current.id = id }
        if let name = delta.function?.name, !name.isEmpty { current.name = name }
        if let arguments = delta.function?.arguments { current.arguments += arguments }
        if calls[index] == nil { order.append(index) }
        calls[index] = current
    }

    var completedCalls: [(id: String, name: String, arguments: String)] {
        order.compactMap { index in
            guard let call = calls[index], !call.name.isEmpty else { return nil }
            let id = call.id.isEmpty ? "call_\(index)" : call.id
            return (id, call.name, call.arguments)
        }
    }
}

enum MyCoderAutoFreeError: LocalizedError {
    case noFreeModels
    case rateLimited(String)
    case modelUnavailable(String, String)
    case emptyResponse
    case apiError(String)
    /// An explicit upstream free-tier rejection halts failover because trying
    /// another model does not supply the required client context.
    case freeTierBlocked(String)

    private static let maximumMessageCharacters = 400

    private struct ServerError {
        let type: String
        let message: String

        var isMissingSession: Bool {
            type.lowercased() == "missingsessionid"
                || MyCoderAutoFreeError.hasMissingSessionMessage(message)
        }

        var isFreeTierGate: Bool {
            !isMissingSession && (type.lowercased() == "freetiererror" || MyCoderAutoFreeError.hasGateMessage(message))
        }

        var summary: String {
            [type, message].filter { !$0.isEmpty }.joined(separator: ": ")
        }
    }

    /// Only error fields are inspected: assistant content may quote these errors.
    private static func serverError(in text: String) -> ServerError? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let detail: [String: Any]
        if let error = object["error"] as? [String: Any] {
            detail = error
        } else if let type = object["type"] as? String,
                  ["error", "freetiererror", "missingsessionid"].contains(type.lowercased()) {
            detail = object
        } else {
            return nil
        }
        let type = (detail["type"] as? String) ?? (detail["code"] as? String) ?? ""
        let message = (detail["message"] as? String) ?? ""
        guard !type.isEmpty || !message.isEmpty else { return nil }
        return ServerError(type: type == "error" ? "" : type, message: message)
    }

    private static func hasGateMessage(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("only be used from within opencode") || lower.contains("only be used in opencode")
    }

    private static func hasMissingSessionMessage(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("missingsessionid") || lower.contains("missing session id")
    }

    private static func boundedMessage(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(maximumMessageCharacters)) + (trimmed.count > maximumMessageCharacters ? "…" : "")
    }

    /// An HTTP status alone cannot establish why the upstream rejected a request.
    static func isFreeTierGate(statusCode: Int, body: String) -> Bool {
        guard statusCode == 400 || statusCode == 403 else { return false }
        if let error = serverError(in: body) { return error.isFreeTierGate }
        // Plain-text HTTP errors are valid too, but JSON content is not an error envelope.
        guard (try? JSONSerialization.jsonObject(with: Data(body.utf8))) == nil else { return false }
        return hasGateMessage(body) && !hasMissingSessionMessage(body)
    }

    /// Pure HTTP→error mapping shared by validate() and tests.
    static func mapHttpError(statusCode: Int, body: String, operation: String) -> MyCoderAutoFreeError {
        let error = serverError(in: body)
        let message = boundedMessage(error?.summary ?? body)
        let suffix = message.isEmpty ? "" : ": \(message)"
        if error?.isMissingSession == true || hasMissingSessionMessage(body) {
            return .apiError("OpenCode request failed (HTTP \(statusCode))\(suffix)")
        }
        if isFreeTierGate(statusCode: statusCode, body: body) {
            return .freeTierBlocked(message)
        }
        if statusCode == 429 {
            return .rateLimited("Free model rate limit reached (HTTP 429)\(suffix)")
        }
        if statusCode == 503 {
            return .rateLimited("Free model server is temporarily unavailable (HTTP 503)\(suffix)")
        }
        if [400, 403, 404, 410].contains(statusCode) {
            return .modelUnavailable("unknown", "Free model unavailable (HTTP \(statusCode))\(suffix)")
        }
        return .apiError("Free model request failed (HTTP \(statusCode))\(suffix)")
    }

    /// True when `text` is an error envelope carrying the gate (used for both
    /// the REST body and individual SSE data lines).
    static func gateMessage(in text: String) -> String? {
        guard let error = serverError(in: text), error.isFreeTierGate else { return nil }
        return boundedMessage(error.summary)
    }

    static func streamError(in text: String) -> MyCoderAutoFreeError? {
        guard let error = serverError(in: text) else { return nil }
        if error.isFreeTierGate { return .freeTierBlocked(boundedMessage(error.summary)) }
        return .apiError("OpenCode streaming error: \(boundedMessage(error.summary))")
    }

    var errorDescription: String? {
        switch self {
        case .noFreeModels:
            return "OpenCode currently reports no eligible free models."
        case .rateLimited(let message), .apiError(let message):
            return message
        case .modelUnavailable(let model, let message):
            return "OpenCode model \(model) is unavailable. \(message)"
        case .emptyResponse:
            return "OpenCode returned an empty response."
        case .freeTierBlocked(let message):
            return "OpenCode rejected the free-tier request. \(Self.boundedMessage(message)) Use OpenCode, select a configured Zen provider for paid models, or choose another provider."
        }
    }
}
