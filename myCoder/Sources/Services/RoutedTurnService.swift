import Foundation

/// UI-facing status of one routed turn. `failed` always carries the honest
/// message naming the failed node; no status pretends success it did not earn.
enum RoutedTurnStatus: Equatable, Sendable {
    case completed
    case reviewLimitReached
    case cancelled
    case failed(message: String)
}

/// Everything the routed executor needs, captured as Sendable values on the
/// main actor before the turn leaves for the background.
struct RoutedTurnSnapshot: Sendable {
    var configuration: ModelRoutingConfiguration
    var primary: ModelAssignment
    var context: RoleTransportContext
    /// providerID → modelIDs catalog snapshot used for pre-send validation.
    var availableModels: [String: [String]]
    /// Catalog vision facts per assignment (nil value = "not reported").
    var visionSupport: [ModelAssignment: Bool]
    /// Whether the composer's main model supports vision (nil = unknown).
    var mainSupportsVision: Bool?
    var agentMode: AgentMode
    var sessionID: String?
    /// Fully composed request text (system + context + user message).
    var request: String
    var images: [ClipboardImage]
}

/// Full evidence of one routed turn for the chat message and the panel.
struct RoutedTurnOutcome: Sendable {
    var status: RoutedTurnStatus
    var finalText: String?
    var entries: [TurnRouteJournalEntry]
    var usage: UsageCapture?
    var chips: [String]
    var rawResponses: [String]?
}

/// Pure presentation/aggregation logic of a routed turn. No UI, no network —
/// every function is testable from journal entries alone.
enum RoutedTurnLogic {

    /// Sums provider-reported tokens of all journalled nodes into one capture.
    ///
    /// Вход: журнал узлов хода. Выход: `UsageCapture` с modelID «routed:N
    /// nodes» и providerID из всех провайдеров (sorted, «+»); nil, если ни
    /// один провайдер не сообщил токенов.
    /// Зависимости: `UsageCapture`, `TurnRouteJournalEntry`.
    static func aggregateUsage(entries: [TurnRouteJournalEntry]) -> UsageCapture? {
        let prompt = entries.reduce(0) { $0 + ($1.usage?.inputTokens ?? 0) }
        let completion = entries.reduce(0) { $0 + ($1.usage?.outputTokens ?? 0) }
        guard prompt > 0 || completion > 0 else { return nil }
        let providerID = Set(entries.map(\.assignment.providerID)).sorted().joined(separator: "+")
        return UsageCapture(
            promptTokens: prompt,
            completionTokens: completion,
            costUSD: nil,
            modelID: "routed:\(entries.count) nodes",
            providerID: providerID
        )
    }

    /// Per-node route chips: «Role → provider/model», ⚠️ for unfinished nodes.
    ///
    /// Вход: журнал узлов. Выход: строки для `MessagePartContent.routeInfo`.
    /// Зависимости: `TurnRouteJournalEntry.isCompleted`.
    static func chips(entries: [TurnRouteJournalEntry]) -> [String] {
        entries.map { entry in
            let prefix = entry.isCompleted ? "" : "⚠️ "
            return "\(prefix)\(entry.role.displayName) → \(entry.assignment.providerID)/\(entry.assignment.modelID)"
        }
    }

    /// Honest failure text: names the failed node, its real assignment and the
    /// fact that no alternative provider was silently used (M1 contract).
    ///
    /// Вход: журнал (ищем последний узел с ошибкой), ошибка графа.
    /// Выход: пользовательское сообщение.
    /// Зависимости: `TurnRouteJournalEntry`.
    static func failureMessage(entries: [TurnRouteJournalEntry], error: Error) -> String {
        guard let failed = entries.last(where: { $0.error != nil }) else {
            return "\(error.localizedDescription) No fallback provider was used."
        }
        let detail = failed.error ?? error.localizedDescription
        return "Route failed at \(failed.role.displayName) (\(failed.assignment.providerID)/\(failed.assignment.modelID)): \(detail) No fallback provider was used."
    }

    /// Visible degradation for the review limit: the concrete findings plus
    /// the last real draft, so the user never loses produced work.
    ///
    /// Вход: отчёт графа с outcome .reviewLimitReached.
    /// Выход: текст для сообщения чата.
    /// Зависимости: `ReviewResponseParser`.
    static func reviewLimitText(report: TurnRouteReport) -> String {
        let findings = report.entries.last(where: { $0.role == .review })?.result ?? ""
        let draft = report.entries.last(where: { $0.role == .execution || $0.role == .correction })?.result ?? ""
        var text = "Review limit reached: the reviewer still reports findings, so the answer is NOT marked complete.\n\nFindings:\n\(findings)"
        if !draft.isEmpty {
            text += "\n\nLast draft:\n\(draft)"
        }
        return text
    }

    /// Reads attached files that are real images into transportable payloads.
    ///
    /// Вход: файлы вложения. Выход: `ClipboardImage` только для файлов, чей
    /// mime по каталогу — изображение и чьё содержимое действительно читается.
    /// Зависимости: `MessagePartsBuilder`, `ClipboardImage.init?(imageData:)`.
    static func imageAttachments(files: [FileInfo]) -> [ClipboardImage] {
        files.compactMap { file in
            guard let path = file.path, !path.isEmpty else { return nil }
            let mime = MessagePartsBuilder.mimeType(for: file)
            guard MessagePartsBuilder.isImageMimeType(mime),
                  let data = FileManager.default.contents(atPath: path),
                  let image = ClipboardImage(imageData: data, mimeType: mime) else { return nil }
            return image
        }
    }

    /// Pre-send validation of EVERY node the graph can execute, against the
    /// real catalog. Fails loudly before any request leaves the machine.
    ///
    /// Вход: граф, резолвер, каталог моделей, vision-факты каталога.
    /// Выход: throws `ModelRoutingError` при любой неполноте/недоступности;
    /// .correction валидируется всегда, когда в графе есть .review.
    /// Зависимости: `ModelRouteResolver.validatedAssignment`.
    static func validateAllRoles(
        graph: TurnRouteGraph,
        resolver: ModelRouteResolver,
        availableModels: [String: [String]],
        visionSupport: [ModelAssignment: Bool]
    ) throws {
        var roles = graph.initialRoles
        if roles.contains(.review), !roles.contains(.correction) {
            roles.append(.correction)
        }
        for role in roles {
            let assignment = try resolver.validatedAssignment(for: role, availableModels: availableModels)
            if role == .vision, visionSupport[assignment] == false {
                throw ModelRoutingError.visionUnavailable
            }
        }
    }

    /// Folds the runner outcome into the UI-facing result. The journal is
    /// preserved on every path: failure, cancellation and review limit.
    ///
    /// Вход: отчёт графа + ошибка (если граф не дошёл до конца).
    /// Выход: `RoutedTurnOutcome`.
    /// Зависимости: `aggregateUsage`, `chips`, `failureMessage`, `reviewLimitText`.
    static func outcome(report: TurnRouteReport, error: Error?) -> RoutedTurnOutcome {
        let status: RoutedTurnStatus
        let finalText: String?
        if let error {
            if error is CancellationError {
                status = .cancelled
                finalText = nil
            } else {
                status = .failed(message: failureMessage(entries: report.entries, error: error))
                finalText = nil
            }
        } else if report.outcome == .reviewLimitReached {
            status = .reviewLimitReached
            finalText = reviewLimitText(report: report)
        } else {
            status = .completed
            finalText = report.finalText
        }
        let raw = report.entries.flatMap { $0.rawResponses ?? [] }
        return RoutedTurnOutcome(
            status: status,
            finalText: finalText,
            entries: report.entries,
            usage: aggregateUsage(entries: report.entries),
            chips: chips(entries: report.entries),
            rawResponses: raw.isEmpty ? nil : raw
        )
    }
}

/// Executes one routed turn from a captured snapshot. Thin orchestration over
/// `TurnRouteGraph` + `RoleRequestExecutor`; all decision logic is pure and
/// lives in `RoutedTurnLogic` / `RoutedImagesPolicy`.
enum RoutedTurnExecutor {

    /// Runs the whole graph for one send.
    ///
    /// Вход: снимок (конфигурация, каталог, запрос, вложения), progress-колбэк
    /// «узел стартует», опциональный HTTP-транспорт (ТОЛЬКО тесты; в проде nil
    /// → реальный URLSession-транспорт).
    /// Выход: `RoutedTurnOutcome` — статус, финальный текст, журнал всех
    /// выполненных узлов, суммарный usage, chips и сырые ответы.
    /// Зависимости: `TurnRouteGraph`, `TurnRouteRunner`, `ModelRouteResolver`,
    /// `RoutedImagesPolicy`, `RoleRequestExecutor`, `RoleTransportResolver`.
    static func run(
        snapshot: RoutedTurnSnapshot,
        progress: (@Sendable (ModelRole, ModelAssignment) -> Void)? = nil,
        transport: DirectChatTransport? = nil
    ) async -> RoutedTurnOutcome {
        let graph = TurnRouteGraph.build(
            agentMode: snapshot.agentMode,
            hasImages: !snapshot.images.isEmpty,
            mainSupportsVision: snapshot.mainSupportsVision
        )
        let resolver = ModelRouteResolver(configuration: snapshot.configuration, primary: snapshot.primary)

        // 1) Validate every node against the real catalog BEFORE any send.
        do {
            try RoutedTurnLogic.validateAllRoles(
                graph: graph,
                resolver: resolver,
                availableModels: snapshot.availableModels,
                visionSupport: snapshot.visionSupport
            )
        } catch {
            return RoutedTurnOutcome(
                status: .failed(message: error.localizedDescription),
                finalText: nil, entries: [], usage: nil, chips: [], rawResponses: nil
            )
        }

        // 2) Decide which nodes carry the original images (catalog facts only).
        let context = snapshot.context
        let carriers = RoutedImagesPolicy.imageCarryingRoles(
            roles: graph.initialRoles,
            primary: snapshot.primary,
            assignments: { resolver.assignment(for: $0) },
            visionSupport: { snapshot.visionSupport[$0] },
            transportKind: { RoleTransportResolver.kind(for: $0, context: context) }
        )

        // 3) Vision fallback is mandatory: if the graph needs a vision node
        //    but no carrier can physically take the images — fail honestly.
        if graph.requiresVisionFallback, !carriers.contains(.vision) {
            return RoutedTurnOutcome(
                status: .failed(message: ModelRoutingError.visionUnavailable.localizedDescription),
                finalText: nil, entries: [], usage: nil, chips: [], rawResponses: nil
            )
        }

        // 4) Execute the graph; the executor is created INSIDE the sendable
        //    closure because RoleRequestExecutor is not Sendable.
        let images = snapshot.images
        let runOutcome = await TurnRouteRunner(
            configuration: snapshot.configuration,
            primary: snapshot.primary,
            graph: graph
        ).runCollecting(sessionID: snapshot.sessionID, request: snapshot.request) { role, assignment, input in
            var executor = RoleRequestExecutor(context: context)
            if let transport { executor.directTransport = transport }
            progress?(role, assignment)
            return try await executor.send(
                role: role,
                assignment: assignment,
                input: input,
                images: carriers.contains(role) ? images : []
            )
        }
        return RoutedTurnLogic.outcome(report: runOutcome.report, error: runOutcome.error)
    }
}
