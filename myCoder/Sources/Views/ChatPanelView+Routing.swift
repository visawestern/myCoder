import Foundation

/// M1 routing helpers of the composer. Everything here reads `AppState` on the
/// main actor and hands back Sendable values or closures, so the actual send /
/// compaction / planning can leave for the background without dragging UI
/// state along. The heavy execution itself lives in `RoutedTurnService`.
extension ChatPanelView {

    /// Project root used for the project-scope routing default.
    ///
    /// Вход: нет (текущая сессия/воркспейс). Выход: нормализованный путь.
    /// Зависимости: `SessionProjectRootLogic`.
    func routingProjectRoot() -> String {
        SessionProjectRootLogic.resolve(
            sessionDirectory: appState.selectedSession?.directory,
            selectedWorkspacePath: appState.selectedWorkspace?.path
        )
    }

    /// Reloads routing configuration + executed-route journal for the current
    /// chat. Safe from any context: hops to the main actor itself.
    ///
    /// Вход: нет. Выход: обновлённые `modelRoutingConfiguration`/`modelRouteJournal`.
    /// Зависимости: `AppState.loadModelRouting`.
    func reloadModelRouting() {
        Task { @MainActor in
            appState.loadModelRouting(
                projectRoot: routingProjectRoot(),
                sessionID: appState.selectedSession?.id
            )
        }
    }

    /// Captures every Sendable input the routed executor needs, on the main
    /// actor, before the turn leaves for the background.
    ///
    /// Вход: id чата, собранный текст запроса, режим, файлы и изображения.
    /// Выход: `RoutedTurnSnapshot` (конфигурация, каталог, vision-факты).
    /// Зависимости: `AppState.roleTransportContext/primaryModelAssignment/
    /// catalogVisionSupport`, `RoleTransportResolver`, `RoutedTurnLogic`.
    @MainActor
    func buildRoutedTurnSnapshot(
        sessionID: String?,
        request: String,
        agentMode: AgentMode,
        files: [FileInfo],
        images: [ClipboardImage]
    ) -> RoutedTurnSnapshot {
        let configuration = appState.modelRoutingConfiguration
        let primary = appState.primaryModelAssignment()
        let context = appState.roleTransportContext(agentMode: agentMode)
        let resolver = ModelRouteResolver(configuration: configuration, primary: primary)
        // Vision facts come from the REAL catalog per assignment; a model the
        // catalog does not describe stays absent (nil semantics), never a guess.
        var visionSupport: [ModelAssignment: Bool] = [:]
        for assignment in Set(resolver.resolvedAssignments.values) {
            if let support = appState.catalogVisionSupport(for: assignment) {
                visionSupport[assignment] = support
            }
        }
        var allImages = images
        allImages.append(contentsOf: RoutedTurnLogic.imageAttachments(files: files))
        return RoutedTurnSnapshot(
            configuration: configuration,
            primary: primary,
            context: context,
            availableModels: RoleTransportResolver.availableModels(context: context),
            visionSupport: visionSupport,
            mainSupportsVision: appState.catalogVisionSupport(for: primary),
            agentMode: agentMode,
            sessionID: sessionID,
            request: request,
            images: allImages
        )
    }

    /// Compaction transport for per-role mode: sends the summary prompt to the
    /// model assigned to the .compaction role and journals the node — success
    /// AND failure, so the panel shows what really ran.
    ///
    /// Вход: id чата (для журнала). Выход: `ConversationSummarizer.Transport`.
    /// Зависимости: `ModelRouteResolver`, `RoleRequestExecutor`,
    /// `AppState.recordRouteJournalEntry`.
    @MainActor
    func routedCompactionTransport(sessionID: String?) -> ConversationSummarizer.Transport {
        let configuration = appState.modelRoutingConfiguration
        let primary = appState.primaryModelAssignment()
        let context = appState.roleTransportContext()
        let availableModels = RoleTransportResolver.availableModels(context: context)
        let state = appState
        let capturedSessionID = sessionID
        return { prompt in
            let resolver = ModelRouteResolver(configuration: configuration, primary: primary)
            let assignment = try resolver.validatedAssignment(for: .compaction, availableModels: availableModels)
            let startedAt = Date()
            do {
                let result = try await RoleRequestExecutor(context: context)
                    .send(role: .compaction, assignment: assignment, input: prompt)
                await MainActor.run {
                    state.recordRouteJournalEntry(TurnRouteJournalEntry(
                        id: UUID().uuidString,
                        sessionID: capturedSessionID,
                        role: .compaction,
                        assignment: assignment,
                        startedAt: startedAt,
                        finishedAt: Date(),
                        inputArtifacts: ["conversation-summary"],
                        result: result.text,
                        usage: result.usage,
                        rawResponses: result.rawResponses,
                        error: nil
                    ))
                }
                return result.text
            } catch {
                await MainActor.run {
                    state.recordRouteJournalEntry(TurnRouteJournalEntry(
                        id: UUID().uuidString,
                        sessionID: capturedSessionID,
                        role: .compaction,
                        assignment: assignment,
                        startedAt: startedAt,
                        finishedAt: nil,
                        inputArtifacts: ["conversation-summary"],
                        result: nil,
                        usage: nil,
                        rawResponses: nil,
                        error: error.localizedDescription
                    ))
                }
                throw error
            }
        }
    }

    /// Planning completion closure for per-role mode: the internal context
    /// planner runs on the model assigned to the .planning role. Returned for
    /// EVERY per-role send — an unusable assignment must throw inside the
    /// planner and surface as its visible `.fallback` degradation instead of
    /// silently planning on another model (M1 no-hidden-fallback contract).
    ///
    /// Вход: режим агента, id чата. Выход: closure или nil (single-режим).
    /// Зависимости: `ModelRouteResolver`, `RoleRequestExecutor`,
    /// `AppState.recordRouteJournalEntry`.
    @MainActor
    func routedPlanningComplete(
        agentMode: AgentMode,
        sessionID: String?
    ) -> (@Sendable ([DirectChatMessage]) async throws -> String)? {
        guard appState.modelRoutingConfiguration.mode == .perRole else { return nil }
        let configuration = appState.modelRoutingConfiguration
        let primary = appState.primaryModelAssignment()
        let context = appState.roleTransportContext(agentMode: agentMode)
        let availableModels = RoleTransportResolver.availableModels(context: context)
        let state = appState
        let capturedSessionID = sessionID
        return { messages in
            let resolver = ModelRouteResolver(configuration: configuration, primary: primary)
            let assignment = try resolver.validatedAssignment(for: .planning, availableModels: availableModels)
            let prompt = messages
                .map { "\($0.role.uppercased()): \($0.content)" }
                .joined(separator: "\n\n")
            let startedAt = Date()
            do {
                let result = try await RoleRequestExecutor(context: context)
                    .send(role: .planning, assignment: assignment, input: prompt)
                await MainActor.run {
                    state.recordRouteJournalEntry(TurnRouteJournalEntry(
                        id: UUID().uuidString,
                        sessionID: capturedSessionID,
                        role: .planning,
                        assignment: assignment,
                        startedAt: startedAt,
                        finishedAt: Date(),
                        inputArtifacts: ["context-planner"],
                        result: result.text,
                        usage: result.usage,
                        rawResponses: result.rawResponses,
                        error: nil
                    ))
                }
                return result.text
            } catch {
                await MainActor.run {
                    state.recordRouteJournalEntry(TurnRouteJournalEntry(
                        id: UUID().uuidString,
                        sessionID: capturedSessionID,
                        role: .planning,
                        assignment: assignment,
                        startedAt: startedAt,
                        finishedAt: nil,
                        inputArtifacts: ["context-planner"],
                        result: nil,
                        usage: nil,
                        rawResponses: nil,
                        error: error.localizedDescription
                    ))
                }
                throw error
            }
        }
    }

    /// Sub-agent transport: single mode inherits the caller's transport;
    /// per-role mode delegates to the pure `SubagentTransportResolver`, which
    /// runs sub-agents on the `.research` role — but only when it resolves to
    /// a direct OpenAI-compatible model. Anything else
    /// (serve/web/ACP/unresolved) is an explicit `.unsupported` with the
    /// honest reason, never a detour to the composer's model.
    ///
    /// Вход: транспорт одиночного режима (используется в single). Выход: транспорт.
    /// Зависимости: `SubagentTransportResolver`, `AppState`.
    @MainActor
    func routedSubagentTransport(fallback: SubagentRunner.Transport) -> SubagentRunner.Transport {
        SubagentTransportResolver.transport(
            configuration: appState.modelRoutingConfiguration,
            primary: appState.primaryModelAssignment(),
            context: appState.roleTransportContext(),
            fallback: fallback
        )
    }
}
