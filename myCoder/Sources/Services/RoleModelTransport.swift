import Foundation

/// Catalog snapshot needed to resolve ANY role assignment (not just the
/// composer's current selection) into a concrete transport. Values only —
/// credentials stay in their existing secure stores and are read through the
/// same accessors the single-model path uses.
struct RoleTransportContext: Sendable {
    let customProviders: [CustomProvider]
    let localProviders: [LocalProviderConfig]
    let serverProviders: [MimoProviderResponse]
    let serverConnected: Bool
    let webProviderIDs: [String]
    /// Port of the local MiMo Serve used for ephemeral role sessions.
    let serverPort: Int
    let agentMode: AgentMode

    init(
        customProviders: [CustomProvider],
        localProviders: [LocalProviderConfig],
        serverProviders: [MimoProviderResponse],
        serverConnected: Bool,
        webProviderIDs: [String],
        serverPort: Int,
        agentMode: AgentMode
    ) {
        self.customProviders = customProviders
        self.localProviders = localProviders
        self.serverProviders = serverProviders
        self.serverConnected = serverConnected
        self.webProviderIDs = webProviderIDs
        self.serverPort = serverPort
        self.agentMode = agentMode
    }
}

/// The concrete transport that will carry one role request. Every unsupported
/// shape is an explicit case — the executor fails honestly instead of quietly
/// choosing another provider (M1: hidden cross-provider fallback is banned).
enum RoleTransportKind: Equatable {
    /// OpenAI-compatible HTTP endpoint (Ollama/STRATA/custom cloud providers).
    case openAICompatible(baseURL: String, apiKey: String?, model: String)
    /// Local `opencode serve` session REST API (ephemeral session per role).
    case openCodeServe(baseURL: String, headers: [String: String], providerID: String, model: String)
    /// Built-in MiMo Serve (ephemeral session per role request).
    case mimoServe(model: String, providerID: String)
    /// ACP-enabled custom provider (ACPClient chat completion).
    case acp(baseURL: String, apiKey: String, model: String)
    /// Browser web-chat provider: cannot run one-shot role requests.
    case webUnsupported(configID: String)
    /// Nothing usable: the provider is unknown, disabled or disconnected.
    case unresolved
}

/// Pure resolver from a role assignment to its transport kind. Mirrors the
/// route order of `SendRouteResolver.route`, but derives the ACP status from
/// the assignment's own provider (not from the composer's current selection).
enum RoleTransportResolver {
    /// Determines the transport for one assignment against the catalog.
    ///
    /// Вход: назначение роли (provider/model), снимок каталога провайдеров.
    /// Выход: конкретный `RoleTransportKind`; web и неизвестные провайдеры —
    /// явные неуспешные кейсы, никогда не подмена другим провайдером.
    /// Зависимости: `WebProviderConnectivity`, `LocalProviderConfig.authHeaders`,
    /// `CustomProvider.getSecureAPIKey`.
    static func kind(for assignment: ModelAssignment, context: RoleTransportContext) -> RoleTransportKind {
        // 1) Web provider (option id "web:<id>") — interactive browser only.
        if let webID = WebProviderConnectivity.configID(fromOptionID: assignment.providerID),
           context.webProviderIDs.contains(webID) {
            return .webUnsupported(configID: webID)
        }
        // 2) Local provider (Ollama/STRATA → OpenAI HTTP; OpenCode → serve REST).
        if let local = context.localProviders.first(where: { $0.id == assignment.providerID && $0.isEnabled }) {
            switch local.kind {
            case .ollama, .strata:
                return .openAICompatible(baseURL: "\(local.apiBaseURL)/v1", apiKey: nil, model: assignment.modelID)
            case .openCode:
                return .openCodeServe(baseURL: local.apiBaseURL, headers: local.authHeaders(),
                                      providerID: local.openCodeProviderID, model: assignment.modelID)
            }
        }
        // 3) Custom provider: ACP-enabled ones speak the ACP protocol, the
        //    rest are OpenAI-compatible. The key is resolved through the same
        //    secure accessor the single-model route uses (audit ARCH-04).
        if let custom = context.customProviders.first(where: { $0.id == assignment.providerID && $0.isEnabled }) {
            let key = (custom.getSecureAPIKey() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if custom.type == .acp && custom.acpEnabled {
                return .acp(baseURL: custom.baseURL, apiKey: key, model: assignment.modelID)
            }
            return .openAICompatible(baseURL: custom.baseURL,
                                     apiKey: key.isEmpty ? nil : key,
                                     model: assignment.modelID)
        }
        // 4) MiMo Serve — only for providers actually in the serve catalog.
        if context.serverConnected,
           context.serverProviders.contains(where: { $0.id == assignment.providerID }) {
            return .mimoServe(model: assignment.modelID, providerID: assignment.providerID)
        }
        return .unresolved
    }

    /// providerID → modelIDs map for catalog validation of role assignments
    /// (web option ids included so the picker can offer them and the send can
    /// fail with the honest web-unsupported error instead of "model gone").
    ///
    /// Вход: снимок каталога. Выход: карта доступных моделей.
    /// Зависимости: `WebProviderStore`, `WebProviderConnectivity`.
    static func availableModels(context: RoleTransportContext) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for local in context.localProviders where local.isEnabled {
            result[local.id] = local.models
        }
        for custom in context.customProviders where custom.isEnabled {
            result[custom.id] = custom.models.sorted()
        }
        for server in context.serverProviders {
            result[server.id] = server.models.keys.sorted()
        }
        for config in WebProviderStore.load() where context.webProviderIDs.contains(config.id) {
            // Option ids are built exactly like `WebProviderConnectivity.providerOptions`.
            result["web:\(config.id)"] = WebProviderConnectivity.models(for: config)
        }
        return result
    }
}

/// Decides which graph nodes carry the original image attachments.
/// Pure and testable: capability comes from the resolved catalog metadata,
/// never from model-name heuristics (M1 contract).
enum RoutedImagesPolicy {
    /// Whether a transport kind can physically carry image parts.
    ///
    /// Вход: вид транспорта. Выход: true для openAI/mimo/ACP.
    /// Зависимости: `RoleTransportKind`.
    static func canCarryImages(_ kind: RoleTransportKind) -> Bool {
        switch kind {
        case .openAICompatible, .mimoServe, .acp: return true
        case .openCodeServe, .webUnsupported, .unresolved: return false
        }
    }

    /// Roles whose request must include the attached images.
    ///
    /// Вход: роли графа (в порядке исполнения), функция назначений,
    /// catalog-факты vision-поддержки по назначениям (nil = «не сообщается»),
    /// функция вида транспорта, первичное назначение композера.
    /// Выход: множество ролей-получателей изображений.
    /// Правила: (1) узел .vision всегда; (2) роли с явным vision == true на
    /// image-транспорте; (3) если vision-узла нет — роли на первичной модели
    /// (паритет с одиночным режимом, capability не «false»); (4) если никто
    /// не может принять изображения — первая image-способная роль (best-effort,
    /// журнал это фиксирует). Пустое множество возможно только когда ни один
    /// транспорт не переносит изображения.
    /// Зависимости: `RoleTransportKind`, `ModelAssignment`.
    static func imageCarryingRoles(
        roles: [ModelRole],
        primary: ModelAssignment,
        assignments: (ModelRole) -> ModelAssignment?,
        visionSupport: (ModelAssignment) -> Bool?,
        transportKind: (ModelAssignment) -> RoleTransportKind
    ) -> Set<ModelRole> {
        var carriers: Set<ModelRole> = []
        var primaryCarriers: Set<ModelRole> = []
        var anyCapable: ModelRole?
        let hasVisionNode = roles.contains(.vision)

        for role in roles {
            guard let assignment = assignments(role) else { continue }
            let kind = transportKind(assignment)
            guard canCarryImages(kind) else { continue }
            if anyCapable == nil { anyCapable = role }
            if role == .vision {
                carriers.insert(role)
                continue
            }
            if visionSupport(assignment) == true {
                carriers.insert(role)
                continue
            }
            if !hasVisionNode,
               assignment == primary,
               visionSupport(assignment) != false {
                primaryCarriers.insert(role)
            }
        }
        if carriers.isEmpty {
            carriers.formUnion(primaryCarriers)
        }
        if carriers.isEmpty, let fallback = anyCapable {
            carriers.insert(fallback)
        }
        return carriers
    }
}

/// Executes one role request over its resolved transport. HTTP kinds run
/// through the injectable `DirectChatTransport` (tests use a scripted fake);
/// MiMo Serve and ACP use their real clients, with explicit test seams that
/// production never sets. Errors are thrown as-is: no retry against another
/// provider, no silent model substitution (M1 contract).
struct RoleRequestExecutor {
    let context: RoleTransportContext
    var directTransport: DirectChatTransport

    /// TEST SEAM (nil in production): replaces the real MimoServeClient call.
    var mimoSendOverride: (@Sendable (ModelAssignment, String, [ClipboardImage], AgentMode) async throws -> ModelRoleResult)? = nil
    /// TEST SEAM (nil in production): replaces the real ACPClient call.
    var acpSendOverride: (@Sendable (ModelAssignment, String, [ClipboardImage]) async throws -> ModelRoleResult)? = nil

    init(context: RoleTransportContext,
         directTransport: DirectChatTransport = URLSessionDirectChatTransport()) {
        self.context = context
        self.directTransport = directTransport
    }

    /// Sends one role request to exactly the assigned model.
    ///
    /// Вход: роль, назначение (provider/model/parameters), собранный текстовый
    /// вход узла, вложения (только для vision-узлов).
    /// Выход: реальный ответ модели с usage; любая недоступность — явная ошибка.
    /// Зависимости: `RoleTransportResolver`, `DirectChatClient`,
    /// `OpenCodeServeClient`, `MimoServeClient`, `ACPClient`.
    func send(role: ModelRole,
              assignment: ModelAssignment,
              input: String,
              images: [ClipboardImage] = []) async throws -> ModelRoleResult {
        let kind = RoleTransportResolver.kind(for: assignment, context: context)
        switch kind {
        case .openAICompatible(let baseURL, let apiKey, let model):
            return try await sendOpenAI(
                baseURL: baseURL, apiKey: apiKey, model: model,
                assignment: assignment, input: input, images: images
            )
        case .openCodeServe(let baseURL, let headers, let providerID, let model):
            // The serve REST message body is text-only: refuse images loudly
            // instead of dropping the attachment (M1 honesty rule).
            guard images.isEmpty else {
                throw ModelRoutingError.imagesUnsupported(role: role, modelID: model)
            }
            let result = try await OpenCodeServeClient.send(
                baseURL: baseURL, headers: headers, modelID: model,
                text: input, providerID: providerID, sessionID: nil,
                transport: directTransport
            )
            return ModelRoleResult(text: result.content)
        case .mimoServe:
            if let mimoSendOverride {
                return try await mimoSendOverride(assignment, input, images, context.agentMode)
            }
            return try await sendMimo(assignment: assignment, input: input, images: images)
        case .acp(let baseURL, let apiKey, let model):
            if let acpSendOverride {
                return try await acpSendOverride(assignment, input, images)
            }
            return try await sendACP(
                baseURL: baseURL, apiKey: apiKey, model: model,
                assignment: assignment, input: input, images: images
            )
        case .webUnsupported(let configID):
            throw ModelRoutingError.webRoleUnsupported(role: role, configID: configID)
        case .unresolved:
            throw ModelRoutingError.unavailableProvider(providerID: assignment.providerID)
        }
    }

    /// OpenAI-compatible one-shot with real multimodal parts for vision.
    ///
    /// Вход: endpoint/key/model из резолвера, параметры назначения, текст,
    /// изображения. Выход: текст, reasoning, usage и сырой ответ провайдера.
    /// Зависимости: `DirectChatClient.send`, `DirectChatMessage.imageParts`.
    private func sendOpenAI(baseURL: String,
                            apiKey: String?,
                            model: String,
                            assignment: ModelAssignment,
                            input: String,
                            images: [ClipboardImage]) async throws -> ModelRoleResult {
        let message: DirectChatMessage
        if images.isEmpty {
            message = DirectChatMessage(role: "user", content: input)
        } else {
            var parts: [[String: Any]] = [["type": "text", "text": input]]
            for image in images {
                parts.append(contentsOf: DirectChatMessage.imageParts(for: image))
            }
            message = DirectChatMessage(role: "user", content: input, parts: parts)
        }
        let result = try await DirectChatClient.send(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            messages: [message],
            parameters: assignment.parameters,
            transport: directTransport
        )
        return ModelRoleResult(
            text: result.content,
            reasoning: result.reasoning,
            usage: result.usage.map {
                ModelRoleUsage(inputTokens: $0.promptTokens, outputTokens: $0.completionTokens)
            },
            rawResponses: result.rawEvents
        )
    }

    /// MiMo Serve role request over a fresh ephemeral session: a role node is
    /// an independent one-shot conversation and must not write into the
    /// visible chat's server session.
    ///
    /// Вход: назначение, текст узла, изображения. Выход: текст ответа сервера.
    /// Зависимости: `MimoServeClient.createSession/sendMessage`,
    /// `MessagePartsBuilder`, `SessionSendLogic`.
    private func sendMimo(assignment: ModelAssignment,
                          input: String,
                          images: [ClipboardImage]) async throws -> ModelRoleResult {
        let client = MimoServeClient(host: "127.0.0.1", port: context.serverPort)
        let session = try await client.createSession(title: String(input.prefix(60)))
        let parts = MessagePartsBuilder.build(text: input, files: [], images: images)
        let options = MessageSendOptions(
            agent: SessionSendLogic.sendMode(for: context.agentMode),
            modelID: assignment.modelID,
            providerID: assignment.providerID
        )
        let responses = try await client.sendMessage(
            sessionID: session.id,
            parts: parts,
            options: options,
            parameters: assignment.parameters
        )
        guard let text = SessionSendLogic.assistantResponse(from: responses)?.textContent,
              ProviderResponseValidationLogic.hasVisibleContent(text) else {
            throw MimoServeError.emptyResponse
        }
        return ModelRoleResult(text: text)
    }

    /// ACP role request as a non-streaming chat completion with real image
    /// parts (vision) — same contract as the interactive ACP branch.
    ///
    /// Вход: endpoint/key/model, назначение, текст, изображения.
    /// Выход: текст, reasoning и usage из ответа ACP.
    /// Зависимости: `ACPClient.sendChatCompletion`, `ACPMessageBuilder`.
    private func sendACP(baseURL: String,
                         apiKey: String,
                         model: String,
                         assignment: ModelAssignment,
                         input: String,
                         images: [ClipboardImage]) async throws -> ModelRoleResult {
        guard let client = ACPClient(baseURLString: baseURL, apiKey: apiKey) else {
            throw ModelRoutingError.unavailableProvider(providerID: baseURL)
        }
        let message = ACPMessageBuilder.buildUserMessage(
            text: input,
            fileNames: [],
            images: images.map { (mimeType: $0.mimeType, base64: $0.base64) }
        )
        let response = try await client.sendChatCompletion(
            messages: [message],
            model: model,
            agent: SessionSendLogic.sendMode(for: context.agentMode),
            parameters: assignment.parameters,
            stream: false
        )
        let text = response.choices.first?.message.content ?? ""
        guard ProviderResponseValidationLogic.hasVisibleContent(text) else {
            throw ACPError.emptyResponse
        }
        return ModelRoleResult(
            text: text,
            reasoning: response.choices.first?.message.reasoning,
            usage: response.usage.map {
                ModelRoleUsage(inputTokens: $0.promptTokens, outputTokens: $0.completionTokens)
            }
        )
    }
}
