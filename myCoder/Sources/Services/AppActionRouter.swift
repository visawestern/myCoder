import Foundation

/// Ошибки диспетчера действий (отражаются как HTTP-ошибки API).
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

/// Описание запроса на откат диалога (`chat.rollback`). Чистая структура:
/// разбор параметров выполняется без AppState/UI и покрыт юнит-тестами.
struct RollbackRequest: Equatable, Sendable {
    let messageID: String
    let chatID: String?
}

/// Semantic bridge between the local HTTP API and AppState. Every mutation is
/// applied on the main actor; the endpoint catalog lives in
/// `AppActionRouter+Catalog.swift`, domain handlers in the sibling
/// `AppActionRouter+*` files. The catalog is the discovery contract for
/// automation clients (and mirrors the app's primary buttons/commands).
@MainActor
final class AppActionRouter {
    static let shared = AppActionRouter()

    private init() {}

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

        case "context.compaction.stop", "context.compaction.rollback", "context.compaction.retry":
            // The compaction lives in the chat panel (it owns the task and
            // the message store), so the router only asks for the action.
            let control = String(action.split(separator: ".").last ?? "")
            NotificationCenter.default.post(
                name: .apiCompactionControlRequested,
                object: nil,
                userInfo: ["action": control]
            )
            return ["status": "requested", "action": control]

        case "context.compaction.chooseModel":
            // The model menu of the banner is a choice too — it must be
            // reachable without the accessibility tree.
            let providerID = try requireString("providerID", params)
            let modelID = try requireString("modelID", params)
            NotificationCenter.default.post(
                name: .apiCompactionControlRequested,
                object: nil,
                userInfo: [
                    "action": "chooseModel",
                    "providerID": providerID,
                    "modelID": modelID
                ]
            )
            return ["status": "requested", "action": "chooseModel",
                    "providerID": providerID, "modelID": modelID]

        case "browser.fetch":
            return try await BrowserFetchAPILogic.perform(params: params) { arguments in
                // This closure is entered only after pure validation succeeds.
                // Acquiring the app-owned bridge preserves the normal lazy
                // EngineStatusCenter -> BrowserProcess lifecycle.
                let bridge = AntiBrowserTabManager.shared.bridge(tabKey: "internal-api|global|browser-fetch")
                var executor = ProjectWebToolExecutor(projectRoot: appState.toolWorkingDirectory,
                                                      accessLevel: appState.accessLevel)
                executor.bridge = bridge
                return await executor.execute(WebToolCall(name: WebEmulatedTool.browserFetch.rawValue,
                                                          arguments: arguments))
            }

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

        case "goal.state":
            return goalState(appState: appState, params: params)
        case "goal.list":
            let context = goalContext(appState: appState, params: params)
            let goals = GoalContextLogic.visibleGoals(
                GoalStore.load(homeDirectory: Self.homeDirectory),
                context: context
            )
            return ["goals": goals.map(goalRow)]
        case "goal.create":
            let title = try requireString("title", params)
            return try applyGoal(.create(title: title), appState: appState, params: params)
        case "goal.start":
            return try applyGoal(.start, appState: appState, params: params)
        case "goal.pause":
            return try applyGoal(.pause, appState: appState, params: params)
        case "goal.resume":
            return try applyGoal(.resume, appState: appState, params: params)
        case "goal.delete":
            let index = int(params["index"])
            return try applyGoal(.delete(index: index), appState: appState, params: params)
        case "goal.edit":
            let title = try requireString("title", params)
            return try applyGoal(.edit(title: title), appState: appState, params: params)
        case "goal.verify":
            let answer = params["answer"] as? String ?? ""
            return try await verifyGoal(answer: answer, appState: appState, params: params)

        case "ui.screenshot":
            return try screenshot(params: params)
        case "ui.screenshots.list":
            return ["screenshots": ScreenshotsStore.list().map(\.dictionary)]

        case "chat.rollback":
            // Полный откат диалога к запросу: тот же путь, что и кнопка
            // «Откатить к этому запросу» в чате (уведомление rollbackRequested).
            let request = try Self.rollbackRequest(
                params: params,
                defaultChatID: appState.selectedSession?.id
            )
            NotificationCenter.default.post(
                name: .rollbackRequested,
                object: nil,
                userInfo: ["messageId": request.messageID, "chatId": request.chatID ?? ""]
            )
            return ["ok": true, "messageId": request.messageID, "chatId": request.chatID ?? ""]

        default:
            throw AppActionError.unknownAction(action)
        }
    }

    /// Чистый разбор параметров `chat.rollback` (покрыт юнит-тестами).
    ///
    /// `nonisolated`: парсер не трогает AppState/UI, поэтому не должен
    /// наследовать `@MainActor` роутера — иначе его нельзя вызвать из
    /// синхронного юнит-теста (это ломало сборку тестового таргета).
    nonisolated static func rollbackRequest(params: [String: Any], defaultChatID: String? = nil) throws -> RollbackRequest {
        // Пробельный идентификатор — это отсутствующий идентификатор: API
        // клиенты часто шлют " " вместо пустой строки.
        let trimmedMessageID = (params["messageId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedMessageID.isEmpty else {
            throw AppActionError.missingParameter("messageId")
        }
        let trimmedChatID = (params["chatId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let chatID = (trimmedChatID?.isEmpty == false ? trimmedChatID : nil) ?? defaultChatID
        return RollbackRequest(messageID: trimmedMessageID, chatID: chatID)
    }
}
