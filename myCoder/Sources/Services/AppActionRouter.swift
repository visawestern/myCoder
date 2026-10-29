import Foundation

enum AppActionError: LocalizedError {
    case unknownAction(String)
    case missingParameter(String)
    case invalidParameter(String, String)
    case notFound(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unknownAction(let name): return "Unknown action: \(name)"
        case .missingParameter(let name): return "Missing parameter: \(name)"
        case .invalidParameter(let name, let reason): return "Invalid parameter \(name): \(reason)"
        case .notFound(let what): return "Not found: \(what)"
        case .failed(let message): return message
        }
    }
}

/// Semantic bridge between the local HTTP API and AppState. Every mutation is
/// applied on the main actor; the endpoint catalog is the discovery contract
/// for automation clients (and mirrors the app's primary buttons/commands).
@MainActor
final class AppActionRouter {
    static let shared = AppActionRouter()

    private init() {}

    // MARK: - Catalog

    static let catalog: [[String: Any]] = [
        action("app.state", "Return the full UI/state snapshot", []),
        action("app.activate", "Bring the app to the front", []),
        action("app.settings.open", "Open Settings", [param("tab", "string", false, "SettingsTab raw value")]),
        action("app.settings.close", "Close Settings", []),
        action("app.sidebar.toggle", "Show/hide the sidebar", [param("visible", "bool", false, nil)]),
        action("app.terminal.toggle", "Show/hide the terminal panel", [param("visible", "bool", false, nil)]),
        action("app.goal.toggle", "Show/hide the goal/right panel", [param("visible", "bool", false, nil)]),
        action("app.search.toggle", "Show/hide search", [param("visible", "bool", false, nil)]),
        action("app.notifications.toggle", "Show/hide notifications", [param("visible", "bool", false, nil)]),
        action("app.language.set", "Change UI language", [param("language", "string", true, "English|Russian|... or en|ru|es|fr|de|zh|ja|ko|pt|ar")]),
        action("app.agentMode.set", "Change agent mode", [param("mode", "string", true, "Build|Plan|Compose")]),
        action("app.accessLevel.set", "Change permission level", [param("level", "string", true, "Ask before changes|Edit automatically|Full access")]),
        action("app.variant.set", "Change reasoning variant", [param("variant", "string", true, nil)]),
        action("app.flag.set", "Set a boolean app flag", [
            param("name", "string", true, "maxTokens|askBeforeChanges|inputDropdownEnabled"),
            param("value", "bool", true, nil)
        ]),

        action("project.list", "List workspaces", []),
        action("project.state", "Return the selected project state", []),
        action("project.create", "Create/register a project and optionally open the spec wizard", [
            param("name", "string", false, "Defaults to the folder name"),
            param("path", "string", true, "Absolute folder path"),
            param("mode", "string", false, "empty|wizard"),
            param("createDirectory", "bool", false, "Create the folder when missing")
        ]),
        action("project.open", "Open an existing folder as a workspace", [
            param("path", "string", true, nil),
            param("name", "string", false, nil),
            param("createDirectory", "bool", false, nil)
        ]),
        action("project.select", "Select a workspace by id or path", [
            param("id", "string", false, nil),
            param("path", "string", false, nil)
        ]),
        action("project.finder.open", "Reveal a folder in Finder", [param("path", "string", false, "Defaults to the selected workspace")]),
        action("project.creation.begin", "Open the New Project sheet", [param("mode", "string", false, "empty|wizard")]),
        action("project.creation.cancel", "Close the New Project sheet", []),

        action("wizard.state", "Return the spec-wizard draft, turns, revisions and nodes", [param("path", "string", false, nil)]),
        action("wizard.save", "Update the wizard brief/model roles", [
            param("path", "string", false, nil),
            param("goal", "string", false, nil),
            param("stack", "string", false, nil),
            param("constraints", "string", false, nil),
            param("plannerModel", "string", false, nil),
            param("coderModel", "string", false, nil)
        ]),
        action("wizard.interview.start", "Ask the planner for the first interview question", [param("path", "string", false, nil)]),
        action("wizard.answer", "Answer the current planner question", [
            param("path", "string", false, nil),
            param("answer", "string", true, nil)
        ]),
        action("wizard.spec.generate", "Generate a new specification revision", [param("path", "string", false, nil)]),
        action("wizard.spec.edit", "Save an edited specification as a new revision", [
            param("path", "string", false, nil),
            param("markdown", "string", true, nil)
        ]),
        action("wizard.decompose", "Generate the atomic decomposition for the latest revision", [param("path", "string", false, nil)]),
        action("wizard.node.status", "Set a decomposition node status", [
            param("path", "string", false, nil),
            param("nodeId", "string", false, nil),
            param("key", "string", false, nil),
            param("status", "string", true, "pending|running|done|failed|blocked|skipped")
        ]),
        action("wizard.node.start", "Create a coding chat for the next runnable node and queue its prompt", [
            param("path", "string", false, nil),
            param("nodeId", "string", false, nil),
            param("key", "string", false, nil)
        ]),
        action("wizard.node.next", "Return the next runnable node", [param("path", "string", false, nil)]),
        action("wizard.node.linkSession", "Link a chat session to a decomposition node", [
            param("path", "string", false, nil),
            param("nodeId", "string", false, nil),
            param("key", "string", false, nil),
            param("sessionId", "string", false, nil),
            param("state", "string", false, "active|done")
        ]),
        action("wizard.finish", "Finish the wizard (forced or complete)", [
            param("path", "string", false, nil),
            param("forced", "bool", false, nil)
        ]),

        action("session.list", "List chat sessions", []),
        action("session.select", "Select a chat session", [param("id", "string", true, nil)]),
        action("session.new", "Create a standalone chat", [param("title", "string", false, nil)]),
        action("session.rename", "Rename a chat", [param("id", "string", true, nil), param("title", "string", true, nil)]),
        action("session.delete", "Delete a chat", [param("id", "string", true, nil)]),
        action("session.export", "Export a chat transcript as Markdown", [
            param("id", "string", true, nil),
            param("path", "string", false, "Destination .md file; defaults to ~/Downloads")
        ]),
        action("chat.send", "Send a message", [
            param("message", "string", true, nil),
            param("chatId", "string", false, nil),
            param("providerId", "string", false, nil),
            param("modelId", "string", false, nil)
        ]),
        action("chat.stop", "Stop the current generation", []),
        action("toolApproval.resolve", "Allow or deny a pending local tool approval", [
            param("id", "string", true, "Approval id from the app log"),
            param("approved", "bool", true, "true = Allow once, false = Deny")
        ]),

        action("provider.list", "List configured providers and models", []),
        action("provider.select", "Select a provider", [param("id", "string", true, nil)]),
        action("model.select", "Select a model", [param("id", "string", true, nil)]),
        action("model.list", "List models for the selected provider", []),

        action("git.refresh", "Refresh git status for the selected session", []),
        action("git.commit", "Commit all changes", [param("message", "string", true, nil)]),
        action("git.push", "Push the current branch", []),
        action("git.branch.checkout", "Checkout a branch", [param("branch", "string", true, nil)]),

        action("ui.tree", "Dump the accessibility tree of the key window", [
            param("depth", "int", false, "Default 8"),
            param("limit", "int", false, "Default 1200")
        ]),
        action("ui.click", "Press a button by identifier/title/path/index", [
            param("identifier", "string", false, nil),
            param("title", "string", false, nil),
            param("role", "string", false, "Default AXButton"),
            param("path", "string", false, "Tree path such as 0.2.1"),
            param("index", "int", false, "Index in the flattened tree")
        ]),
        action("ui.setValue", "Set the value of a text field by identifier/title/path/index", [
            param("identifier", "string", false, nil),
            param("title", "string", false, nil),
            param("path", "string", false, nil),
            param("index", "int", false, nil),
            param("value", "string", true, nil)
        ])
    ]

    private static func action(_ name: String, _ description: String, _ params: [[String: Any]]) -> [String: Any] {
        ["name": name, "description": description, "params": params]
    }

    private static func param(_ name: String, _ type: String, _ required: Bool, _ description: String?) -> [String: Any] {
        var row: [String: Any] = ["name": name, "type": type, "required": required]
        if let description { row["description"] = description }
        return row
    }

    // MARK: - Dispatch

    @MainActor
    func perform(action: String, params: [String: Any], appState: AppState) async throws -> [String: Any] {
        switch action {
        case "app.state":
            return snapshot(appState: appState)
        case "app.activate":
            AppAccessibilityBridge.activate()
            return ["status": "activated"]
        case "app.settings.open":
            if let raw = params["tab"] as? String, let tab = SettingsTab(rawValue: raw) {
                appState.settingsTab = tab
            }
            appState.showSettings = true
            return ["status": "open", "tab": appState.settingsTab.rawValue]
        case "app.settings.close":
            appState.showSettings = false
            return ["status": "closed"]
        case "app.sidebar.toggle":
            appState.sidebarVisible = bool(params["visible"]) ?? !appState.sidebarVisible
            return ["visible": appState.sidebarVisible]
        case "app.terminal.toggle":
            appState.showTerminal = bool(params["visible"]) ?? !appState.showTerminal
            return ["visible": appState.showTerminal]
        case "app.goal.toggle":
            appState.showGoal = bool(params["visible"]) ?? !appState.showGoal
            return ["visible": appState.showGoal]
        case "app.search.toggle":
            appState.showSearch = bool(params["visible"]) ?? !appState.showSearch
            return ["visible": appState.showSearch]
        case "app.notifications.toggle":
            appState.showNotifications = bool(params["visible"]) ?? !appState.showNotifications
            return ["visible": appState.showNotifications]
        case "app.language.set":
            let raw = try requireString("language", params)
            let language = Self.language(named: raw)
            guard let language else {
                throw AppActionError.invalidParameter("language", raw)
            }
            appState.setLanguage(language)
            return ["language": language.rawValue]
        case "app.agentMode.set":
            let raw = try requireString("mode", params)
            guard let mode = AgentMode(rawValue: raw) else {
                throw AppActionError.invalidParameter("mode", raw)
            }
            appState.agentMode = mode
            return ["mode": mode.rawValue]
        case "app.accessLevel.set":
            let raw = try requireString("level", params)
            guard let level = AccessLevel(rawValue: raw) else {
                throw AppActionError.invalidParameter("level", raw)
            }
            appState.accessLevel = level
            return ["level": level.rawValue]
        case "app.variant.set":
            let raw = try requireString("variant", params)
            appState.selectedVariant = raw
            return ["variant": raw]
        case "app.flag.set":
            let name = try requireString("name", params)
            let value = try requireBool("value", params)
            switch name {
            case "maxTokens": appState.maxTokens = value
            case "askBeforeChanges": appState.askBeforeChanges = value
            case "inputDropdownEnabled": appState.inputDropdownEnabled = value
            default: throw AppActionError.invalidParameter("name", name)
            }
            return ["name": name, "value": value]

        case "project.list":
            return ["workspaces": appState.workspaces.map(workspaceRow)]
        case "project.state":
            return projectState(appState: appState)
        case "project.create":
            return try createProject(params: params, appState: appState)
        case "project.open":
            return try openProject(params: params, appState: appState)
        case "project.select":
            return try selectProject(params: params, appState: appState)
        case "project.finder.open":
            let path = (params["path"] as? String) ?? appState.selectedWorkspace?.path
            guard let path, !path.isEmpty else {
                throw AppActionError.missingParameter("path")
            }
            appState.openFolderInFinder(path)
            return ["status": "opened", "path": path]
        case "project.creation.begin":
            let mode = ProjectCreationMode(rawValue: (params["mode"] as? String) ?? "empty") ?? .empty
            appState.beginProjectCreation(mode: mode)
            return ["showProjectCreation": true, "mode": mode.rawValue]
        case "project.creation.cancel":
            appState.showProjectCreation = false
            return ["showProjectCreation": false]

        case "wizard.state":
            let session = try wizardSession(params: params, appState: appState)
            return wizardState(session: session, appState: appState)
        case "wizard.save":
            let session = try wizardSession(params: params, appState: appState)
            if let goal = params["goal"] as? String { session.draft.goal = goal }
            if let stack = params["stack"] as? String { session.draft.stack = stack }
            if let constraints = params["constraints"] as? String { session.draft.constraints = constraints }
            if let model = params["plannerModel"] as? String { session.draft.plannerModel = model }
            if let model = params["coderModel"] as? String { session.draft.coderModel = model }
            guard session.saveDraft() else {
                throw AppActionError.failed(session.errorMessage ?? "Could not save the wizard draft")
            }
            return wizardState(session: session, appState: appState)
        case "wizard.interview.start":
            let session = try wizardSession(params: params, appState: appState)
            guard session.draft.step == .interview else {
                throw AppActionError.failed("Save the project brief and model roles first")
            }
            await session.submitAnswer("")
            if let error = session.errorMessage { throw AppActionError.failed(error) }
            return wizardState(session: session, appState: appState)
        case "wizard.answer":
            let session = try wizardSession(params: params, appState: appState)
            let answer = try requireString("answer", params)
            await session.submitAnswer(answer)
            if let error = session.errorMessage { throw AppActionError.failed(error) }
            return wizardState(session: session, appState: appState)
        case "wizard.spec.generate":
            let session = try wizardSession(params: params, appState: appState)
            await session.generateSpecification()
            if let error = session.errorMessage { throw AppActionError.failed(error) }
            return wizardState(session: session, appState: appState)
        case "wizard.spec.edit":
            let session = try wizardSession(params: params, appState: appState)
            let markdown = try requireString("markdown", params)
            session.saveSpecificationEdits(markdown)
            if let error = session.errorMessage { throw AppActionError.failed(error) }
            return wizardState(session: session, appState: appState)
        case "wizard.decompose":
            let session = try wizardSession(params: params, appState: appState)
            await session.generateDecomposition()
            if let error = session.errorMessage { throw AppActionError.failed(error) }
            return wizardState(session: session, appState: appState)
        case "wizard.node.status":
            let session = try wizardSession(params: params, appState: appState)
            let node = try resolveNode(params: params, session: session)
            let status = try requireString("status", params)
            guard session.updateNodeStatus(nodeID: node.id, status: status) else {
                throw AppActionError.failed(session.errorMessage ?? "Could not update the node")
            }
            return wizardState(session: session, appState: appState)
        case "wizard.node.start":
            let session = try wizardSession(params: params, appState: appState)
            let node = try resolveNode(params: params, session: session)
            guard let chat = appState.startSpecNodeCoding(wizard: session, node: node) else {
                throw AppActionError.failed(session.errorMessage ?? "Could not start the node")
            }
            let updated = session.nodes.first(where: { $0.id == node.id }) ?? node
            return [
                "chatId": chat.id,
                "node": nodeRow(updated, session: session)
            ]
        case "wizard.node.next":
            let session = try wizardSession(params: params, appState: appState)
            guard let node = session.nextRunnableNode() else {
                return ["node": NSNull(), "reason": "No runnable node"]
            }
            return ["node": nodeRow(node, session: session)]
        case "wizard.node.linkSession":
            let session = try wizardSession(params: params, appState: appState)
            let node = try resolveNode(params: params, session: session)
            let sessionID = try requireString("sessionId", params)
            let state = (params["state"] as? String) ?? "active"
            guard session.linkSession(sessionID, toNode: node.id, state: state) else {
                throw AppActionError.failed(session.errorMessage ?? "Could not link the session")
            }
            return ["status": "linked", "nodeId": node.id, "sessionId": sessionID]
        case "wizard.finish":
            let session = try wizardSession(params: params, appState: appState)
            let forced = bool(params["forced"]) ?? false
            guard session.finishWizard(forced: forced) else {
                throw AppActionError.failed(session.errorMessage ?? "Wizard is not ready")
            }
            appState.finishSpecWizard(for: session.projectPath)
            return wizardState(session: session, appState: appState)

        case "session.list":
            return ["sessions": appState.sessions.map(sessionRow), "selectedSessionId": appState.selectedSession?.id ?? ""]
        case "session.select":
            let id = try requireString("id", params)
            guard let session = appState.sessions.first(where: { $0.id == id })
                    ?? appState.materializeSessionFromDatabase(id: id) else {
                throw AppActionError.notFound("session \(id)")
            }
            appState.selectSession(session)
            return ["selectedSessionId": session.id]
        case "session.new":
            let title = (params["title"] as? String) ?? "New chat"
            let session = appState.createStandaloneSession(title: title)
            // Select through the app so the chat panel reloads the message
            // store; assigning `selectedSession` directly left the previous
            // chat on screen.
            appState.selectSession(session)
            return sessionRow(session)
        case "session.rename":
            let id = try requireString("id", params)
            let title = try requireString("title", params)
            appState.renameSessionInDatabaseUI(id: id, title: title)
            return ["id": id, "title": title]
        case "session.delete":
            let id = try requireString("id", params)
            appState.deleteSessionInDatabaseUI(id: id)
            return ["deleted": id]
        case "session.export":
            let id = try requireString("id", params)
            guard let markdown = appState.sessionTranscriptMarkdown(sessionId: id) else {
                throw AppActionError.notFound("session transcript \(id)")
            }
            let title = appState.sessions.first(where: { $0.id == id })?.title ?? "chat"
            let fileName = SessionTranscriptLogic.fileName(title: title)
            let destination: URL
            if let raw = params["path"] as? String, !raw.isEmpty {
                destination = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
            } else {
                destination = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Downloads", isDirectory: true)
                    .appendingPathComponent(fileName)
            }
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try markdown.write(to: destination, atomically: true, encoding: .utf8)
            return ["path": destination.path, "bytes": markdown.utf8.count]
        case "chat.send":
            let message = try requireString("message", params)
            let target = MyCoderAPIServer.resolveSendTargets(
                appState: appState,
                providerId: params["providerId"] as? String,
                modelId: params["modelId"] as? String,
                chatId: params["chatId"] as? String,
                message: message
            )
            NotificationCenter.default.post(
                name: .apiSendRequested,
                object: nil,
                userInfo: ["message": message, "chatId": target.chatID]
            )
            return [
                "status": "sent",
                "chatId": target.chatID,
                "providerId": target.providerID,
                "modelId": target.modelID
            ]
        case "chat.stop":
            NotificationCenter.default.post(name: .stopGeneration, object: nil)
            return ["status": "stopping"]

        case "provider.list":
            return ["providers": providerRows(appState: appState)]
        case "provider.select":
            let id = try requireString("id", params)
            appState.selectProvider(id, persistPreference: false)
            return ["providerId": appState.selectedProviderID, "modelId": appState.effectiveSelectedModel()]
        case "model.select":
            let id = try requireString("id", params)
            appState.selectModel(id, persistPreference: false)
            return ["modelId": appState.selectedModel]
        case "model.list":
            return ["models": appState.availableModels, "selectedModel": appState.effectiveSelectedModel()]

        case "git.refresh":
            _ = await appState.refreshGitFromLocal()
            return ["status": "refreshed", "message": appState.gitStatusMessage ?? ""]
        case "git.commit":
            let message = try requireString("message", params)
            let ok = await appState.commitGitChanges(message: message)
            return ["committed": ok, "message": appState.gitStatusMessage ?? ""]
        case "git.push":
            await appState.pushGitChanges()
            return ["pushed": true, "message": appState.gitStatusMessage ?? ""]
        case "git.branch.checkout":
            let branch = try requireString("branch", params)
            await appState.checkoutGitBranch(branch)
            return ["branch": branch, "message": appState.gitStatusMessage ?? ""]

        case "toolApproval.resolve":
            let approvalID = try requireString("id", params)
            let approved = try requireBool("approved", params)
            NotificationCenter.default.post(
                name: .localToolApprovalResolved,
                object: nil,
                userInfo: ["approvalID": approvalID, "approved": approved]
            )
            return ["status": "resolved", "approvalID": approvalID, "approved": approved]
        case "ui.tree":
            let depth = int(params["depth"]) ?? 8
            let limit = int(params["limit"]) ?? 1200
            return AppAccessibilityBridge.tree(maxDepth: depth, limit: limit)
        case "ui.click":
            return try AppAccessibilityBridge.click(params: params)
        case "ui.setValue":
            return try AppAccessibilityBridge.setValue(params: params)

        default:
            throw AppActionError.unknownAction(action)
        }
    }

    // MARK: - State snapshots

    @MainActor
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
                "showNotifications": appState.showNotifications
            ],
            "activeSpecWizardProjectPath": appState.activeSpecWizardProjectPath ?? NSNull(),
            "workspaces": appState.workspaces.map(workspaceRow),
            "sessions": appState.sessions.map(sessionRow),
            "selectedSessionId": appState.selectedSession?.id ?? NSNull(),
            "selectedWorkspaceId": appState.selectedWorkspace?.id ?? NSNull(),
            "providers": providerRows(appState: appState)
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

    private func projectState(appState: AppState) -> [String: Any] {
        guard let workspace = appState.selectedWorkspace else {
            return ["workspace": NSNull(), "sessions": appState.sessions.map(sessionRow)]
        }
        return [
            "workspace": workspaceRow(workspace),
            "sessions": appState.sessions.map(sessionRow),
            "selectedSessionId": appState.selectedSession?.id ?? NSNull()
        ]
    }

    private func wizardState(session: SpecWizardSession, appState: AppState) -> [String: Any] {
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

    private func revisionRow(_ revision: ProjectSpecRevision) -> [String: Any] {
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

    private func nodeRow(_ node: ProjectSpecNode, session: SpecWizardSession) -> [String: Any] {
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

    private func questionRow(_ question: SpecInterviewQuestion) -> [String: Any] {
        [
            "id": question.id,
            "question": question.question,
            "suggestedAnswers": question.suggestedAnswers,
            "done": question.done,
            "summary": question.summary ?? NSNull()
        ]
    }

    private func workspaceRow(_ workspace: Workspace) -> [String: Any] {
        [
            "id": workspace.id,
            "name": workspace.name,
            "path": workspace.path,
            "branch": workspace.branch ?? NSNull()
        ]
    }

    private func sessionRow(_ session: ChatSession) -> [String: Any] {
        [
            "id": session.id,
            "title": session.title,
            "directory": session.directory,
            "updatedAt": session.updatedAt.timeIntervalSince1970
        ]
    }

    private func providerRows(appState: AppState) -> [[String: Any]] {
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
                "isConnected": WebProviderConnectivity.isConnected(
                    web,
                    homeDirectory: FileManager.default.homeDirectoryForCurrentUser
                )
            ])
        }
        return rows
    }

    // MARK: - Projects

    private func createProject(params: [String: Any], appState: AppState) throws -> [String: Any] {
        let rawPath = try requireString("path", params)
        let path = ChatSession.normalizedPath((rawPath as NSString).expandingTildeInPath)
        let createDirectory = bool(params["createDirectory"]) ?? false
        if !FileManager.default.fileExists(atPath: path) {
            guard createDirectory else {
                throw AppActionError.notFound("folder \(path)")
            }
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
        let name = (params["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (path as NSString).lastPathComponent
        let mode = ProjectCreationMode(rawValue: (params["mode"] as? String) ?? "empty") ?? .empty
        appState.createNewProject(name: name, path: path)
        if mode == .wizard {
            appState.openSpecWizard(for: path)
            _ = try SpecWizardSessionStore.shared.session(
                projectPath: path,
                projectName: name,
                appState: appState
            )
        }
        var result: [String: Any] = [
            "status": "created",
            "name": name,
            "path": path,
            "mode": mode.rawValue,
            "workspaceId": appState.selectedWorkspace?.id ?? NSNull()
        ]
        if mode == .wizard {
            result["wizard"] = NSNull()
            let session = try SpecWizardSessionStore.shared.session(
                projectPath: path,
                projectName: name,
                appState: appState
            )
            result["wizard"] = wizardState(session: session, appState: appState)
        }
        return result
    }

    private func openProject(params: [String: Any], appState: AppState) throws -> [String: Any] {
        let rawPath = try requireString("path", params)
        let path = ChatSession.normalizedPath((rawPath as NSString).expandingTildeInPath)
        if !FileManager.default.fileExists(atPath: path) {
            guard bool(params["createDirectory"]) ?? false else {
                throw AppActionError.notFound("folder \(path)")
            }
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
        if let existing = appState.workspaces.first(where: {
            ChatSession.normalizedPath($0.path) == path
        }) {
            appState.selectWorkspace(existing)
            return ["status": "opened", "workspace": workspaceRow(existing)]
        }
        let workspace: Workspace
        if let name = params["name"] as? String, !name.isEmpty {
            appState.createNewProject(name: name, path: path)
            workspace = appState.selectedWorkspace ?? appState.addWorkspace(path: path)
        } else {
            workspace = appState.addWorkspace(path: path)
        }
        return ["status": "opened", "workspace": workspaceRow(workspace)]
    }

    private func selectProject(params: [String: Any], appState: AppState) throws -> [String: Any] {
        if let id = params["id"] as? String,
           let workspace = appState.workspaces.first(where: { $0.id == id }) {
            appState.selectWorkspace(workspace)
            return ["status": "selected", "workspace": workspaceRow(workspace)]
        }
        if let rawPath = params["path"] as? String {
            let path = ChatSession.normalizedPath((rawPath as NSString).expandingTildeInPath)
            if let workspace = appState.workspaces.first(where: {
                ChatSession.normalizedPath($0.path) == path
            }) {
                appState.selectWorkspace(workspace)
                return ["status": "selected", "workspace": workspaceRow(workspace)]
            }
            throw AppActionError.notFound("workspace \(path)")
        }
        throw AppActionError.missingParameter("id or path")
    }

    // MARK: - Wizard helpers

    private func wizardSession(params: [String: Any], appState: AppState) throws -> SpecWizardSession {
        let path: String
        if let raw = params["path"] as? String, !raw.isEmpty {
            path = ChatSession.normalizedPath((raw as NSString).expandingTildeInPath)
        } else if let active = appState.activeSpecWizardProjectPath {
            path = active
        } else if let selected = appState.selectedWorkspace {
            path = selected.path
        } else {
            throw AppActionError.missingParameter("path")
        }
        if !FileManager.default.fileExists(atPath: path) {
            throw AppActionError.notFound("folder \(path)")
        }
        let name = appState.workspaces.first(where: {
            ChatSession.normalizedPath($0.path) == path
        })?.name ?? (path as NSString).lastPathComponent
        return try SpecWizardSessionStore.shared.session(
            projectPath: path,
            projectName: name,
            appState: appState
        )
    }

    private func resolveNode(params: [String: Any], session: SpecWizardSession) throws -> ProjectSpecNode {
        if let id = params["nodeId"] as? String,
           let node = session.nodes.first(where: { $0.id == id }) {
            return node
        }
        if let key = params["key"] as? String,
           let node = session.nodes.first(where: { $0.externalKey == key }) {
            return node
        }
        throw AppActionError.notFound("node")
    }

    static func language(named raw: String) -> AppLanguage? {
        if let direct = AppLanguage(rawValue: raw) { return direct }
        switch raw.lowercased() {
        case "en", "english": return .english
        case "ru", "russian": return .russian
        case "es", "spanish": return .spanish
        case "fr", "french": return .french
        case "de", "german": return .german
        case "zh", "chinese": return .chineseSimplified
        case "ja", "japanese": return .japanese
        case "ko", "korean": return .korean
        case "pt", "portuguese": return .portuguese
        case "ar", "arabic": return .arabic
        default: return nil
        }
    }

    private func stateName(_ state: SpecWizardChecklistLogic.ItemState) -> String {
        switch state {
        case .done: return "done"
        case .pending: return "pending"
        case .upcoming: return "upcoming"
        }
    }

    private func jsonValue(_ raw: String?) -> Any? {
        guard let raw, let data = raw.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    // MARK: - Parameter helpers

    private func requireString(_ name: String, _ params: [String: Any]) throws -> String {
        guard let raw = params[name] as? String, !raw.isEmpty else {
            throw AppActionError.missingParameter(name)
        }
        return raw
    }

    private func requireBool(_ name: String, _ params: [String: Any]) throws -> Bool {
        guard let value = bool(params[name]) else {
            throw AppActionError.missingParameter(name)
        }
        return value
    }

    private func bool(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? Int { return value != 0 }
        if let value = value as? String {
            switch value.lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        }
        return nil
    }

    private func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? String { return Int(value) }
        if let value = value as? Double { return Int(value) }
        return nil
    }
}
