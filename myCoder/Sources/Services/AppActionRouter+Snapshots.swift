import Foundation

/// Снапшоты состояния для `app.state`, `project.state`, `wizard.state` и
/// строковые проекции списков (workspace/session/provider/узел/ревзия).
@MainActor
extension AppActionRouter {
    // MARK: - State snapshots

    func snapshot(appState: AppState) -> [String: Any] {
        var state: [String: Any] = [
            "app": [
                "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
                "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "",
                "language": appState.appLanguage.rawValue,
                "isStreaming": appState.isStreaming,
                "isLoading": appState.isLoading,
                "streamingSessionIds": appState.streamingSessionIDs.sorted()
            ],
            "selection": [
                "providerId": appState.selectedProviderID,
                "modelId": appState.effectiveSelectedModel(),
                "variant": appState.selectedVariant,
                "agentMode": appState.agentMode.rawValue,
                "accessLevel": appState.accessLevel.rawValue
            ],
            "ui": [
                "sidebarVisible": appState.sidebarVisible,
                "showTerminal": appState.showTerminal,
                "showGoal": appState.showGoal,
                "showSettings": appState.showSettings,
                "settingsTab": appState.settingsTab.rawValue,
                "showSearch": appState.showSearch,
                "showProjectCreation": appState.showProjectCreation,
                "projectCreationMode": appState.projectCreationMode.rawValue,
                "showNotifications": appState.showNotifications,
                "isLoadingMessages": appState.loadingChatSessionID != nil
            ],
            "activeSpecWizardProjectPath": appState.activeSpecWizardProjectPath ?? NSNull(),
            "workspaces": appState.workspaces.map(workspaceRow),
            "sessions": appState.sessions.map(sessionRow),
            "selectedSessionId": appState.selectedSession?.id ?? NSNull(),
            "selectedWorkspaceId": appState.selectedWorkspace?.id ?? NSNull(),
            "providers": providerRows(appState: appState),
            "context": ContextStateSnapshotLogic.block(
                isPointContextEnabled: appState.isPointContextEnabled,
                isLocalQueryPlannerEnabled: appState.isLocalQueryPlannerEnabled,
                isCompiling: appState.isCompilingContext,
                stageLine: appState.contextPreparationStage,
                internalModels: InternalModelStore.shared.models,
                indexedFileCount: appState.selectedWorkspace
                    .map { ProjectFileIndexStore.load(projectPath: $0.path).count } ?? 0,
                log: appState.contextAssemblyLog
            ),
            "modelSwitchCompaction": ModelSwitchCompactionSnapshotLogic.block(
                appState.modelSwitchCompactionNotice
            )
        ]
        if let path = appState.activeSpecWizardProjectPath,
           let session = SpecWizardSessionStore.shared.session(projectPath: path) {
            state["wizard"] = wizardState(session: session, appState: appState)
        } else if let selected = appState.selectedWorkspace {
            let session = try? SpecWizardSessionStore.shared.session(
                projectPath: selected.path,
                projectName: selected.name,
                appState: appState
            )
            if let session, session.draft.status == .draft {
                state["wizard"] = wizardState(session: session, appState: appState)
            }
        }
        return state
    }

    func projectState(appState: AppState) -> [String: Any] {
        guard let workspace = appState.selectedWorkspace else {
            return ["workspace": NSNull(), "sessions": appState.sessions.map(sessionRow)]
        }
        return [
            "workspace": workspaceRow(workspace),
            "sessions": appState.sessions.map(sessionRow),
            "selectedSessionId": appState.selectedSession?.id ?? NSNull()
        ]
    }

    func wizardState(session: SpecWizardSession, appState: AppState) -> [String: Any] {
        let draft = session.draft
        let checklist = SpecWizardChecklistLogic.items(for: draft).map { item -> [String: Any] in
            [
                "key": item.id.rawValue,
                "state": stateName(item.state),
                "done": item.state == .done
            ]
        }
        let revisions = session.revisionHistory()
        var result: [String: Any] = [
            "projectPath": session.projectPath,
            "projectName": session.projectName,
            "active": appState.activeSpecWizardProjectPath == session.projectPath,
            "draft": [
                "status": draft.status.rawValue,
                // `step` is how far the project has got; `visibleStep` is the
                // screen the user is looking at (they may have navigated back).
                "step": draft.step.rawValue,
                "visibleStep": draft.visibleStep.rawValue,
                "activeStep": draft.activeStep?.rawValue ?? NSNull(),
                "goal": draft.goal,
                "stack": draft.stack,
                "constraints": draft.constraints,
                "plannerModel": draft.plannerModel,
                "coderModel": draft.coderModel,
                "interviewComplete": draft.interviewComplete,
                "specVersion": draft.specVersion,
                "decompositionNodeCount": draft.decompositionNodeCount,
                "updatedAt": draft.updatedAt
            ],
            "checklist": checklist,
            "canFinish": SpecWizardChecklistLogic.canFinish(draft),
            "turns": session.turns.map { ["role": $0.role, "content": $0.content] },
            "currentQuestion": session.currentQuestion.map(questionRow) ?? NSNull(),
            "completedSummary": session.completedSummary ?? NSNull(),
            "specification": session.specification,
            "latestRevision": session.latestRevision.map { revisionRow($0) } ?? NSNull(),
            "nodes": session.nodes.map { nodeRow($0, session: session) },
            "isLoading": session.isLoading,
            "error": session.errorMessage ?? NSNull(),
            "revisions": revisions.map(revisionRow)
        ]
        result["nextRunnableNode"] = session.nextRunnableNode().map { nodeRow($0, session: session) } ?? NSNull()
        return result
    }

    func revisionRow(_ revision: ProjectSpecRevision) -> [String: Any] {
        [
            "id": revision.id,
            "version": revision.version,
            "contentMarkdown": revision.contentMarkdown,
            "summary": revision.summary ?? NSNull(),
            "source": revision.source,
            "parentRevisionId": revision.parentRevisionID ?? NSNull(),
            "createdAt": revision.createdAt
        ]
    }

    func nodeRow(_ node: ProjectSpecNode, session: SpecWizardSession) -> [String: Any] {
        let dependencies = session.dependencies(of: node).map(\.externalKey)
        let linked = session.nodeSessions(for: node.id).map { $0.sessionID }
        return [
            "id": node.id,
            "key": node.externalKey,
            "title": node.title,
            "description": node.description,
            "kind": node.kind,
            "status": node.status,
            "order": node.sortOrder,
            "acceptanceCriteria": jsonValue(node.acceptanceCriteriaJSON) ?? NSNull(),
            "dependsOn": dependencies,
            "sessionIds": linked,
            "revisionId": node.revisionID
        ]
    }

    func questionRow(_ question: SpecInterviewQuestion) -> [String: Any] {
        [
            "id": question.id,
            "question": question.question,
            "suggestedAnswers": question.suggestedAnswers,
            "done": question.done,
            "summary": question.summary ?? NSNull()
        ]
    }

    func workspaceRow(_ workspace: Workspace) -> [String: Any] {
        [
            "id": workspace.id,
            "name": workspace.name,
            "path": workspace.path,
            "branch": workspace.branch ?? NSNull()
        ]
    }

    func sessionRow(_ session: ChatSession) -> [String: Any] {
        [
            "id": session.id,
            "title": session.title,
            "directory": session.directory,
            "updatedAt": session.updatedAt.timeIntervalSince1970
        ]
    }

    func providerRows(appState: AppState) -> [[String: Any]] {
        var rows: [[String: Any]] = []
        for provider in appState.serverProviders {
            rows.append([
                "id": provider.id,
                "name": provider.name,
                "models": provider.models.values.map(\.id).sorted(),
                "isConnected": appState.providerConnectivity[provider.id] ?? false
            ])
        }
        for provider in appState.customProviders {
            rows.append([
                "id": provider.id,
                "name": provider.name,
                "models": provider.models,
                "isConnected": provider.isEnabled
            ])
        }
        for local in LocalProviderLogic.load() where local.isEnabled {
            rows.append([
                "id": local.id,
                "name": local.kind.displayName,
                "models": local.models,
                "isConnected": true
            ])
        }
        for web in WebProviderStore.load(defaults: appState.defaults) {
            rows.append([
                "id": "web:\(web.id)",
                "name": web.displayName,
                "models": web.allModels,
                "isConnected": WebProviderConnectivity.isConnected(web)
            ])
        }
        return rows
    }
}
