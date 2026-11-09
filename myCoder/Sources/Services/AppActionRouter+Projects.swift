import Foundation

/// Действия проекта/wizard: создание, открытие, выбор workspace и хелперы
/// сессии spec-wizard. Вынесены из основного файла (лимит ≤600 строк).
@MainActor
extension AppActionRouter {
    // MARK: - Projects

    func createProject(params: [String: Any], appState: AppState) throws -> [String: Any] {
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

    func openProject(params: [String: Any], appState: AppState) throws -> [String: Any] {
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

    func selectProject(params: [String: Any], appState: AppState) throws -> [String: Any] {
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

    func wizardSession(params: [String: Any], appState: AppState) throws -> SpecWizardSession {
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

    func resolveNode(params: [String: Any], session: SpecWizardSession) throws -> ProjectSpecNode {
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
}
