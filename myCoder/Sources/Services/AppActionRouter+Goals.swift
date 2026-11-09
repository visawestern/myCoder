import Foundation

/// Хелперы цели (ЦЕЛЬ) и скриншотов: общие для `goal.*` и `ui.screenshot`
/// действий. Вынесены из основного файла (лимит ≤600 строк).
@MainActor
extension AppActionRouter {
    // MARK: - ЦЕЛЬ + screenshots helpers

    static var homeDirectory: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// Apply a ЦЕЛЬ goal command through the SAME service the sidebar buttons
    /// and `/goal` use — the API never bypasses a user-doable path.
    ///
    /// The command is scoped to the open chat/project, exactly like the
    /// sidebar: an optional `chatID`/`projectPath` parameter overrides the
    /// current scope for automation clients.
    func applyGoal(_ command: GoalCommand,
                   appState: AppState,
                   params: [String: Any] = [:]) throws -> [String: Any] {
        let context = goalContext(appState: appState, params: params)
        let outcome = try GoalService.apply(
            command,
            homeDirectory: Self.homeDirectory,
            language: appState.appLanguage,
            context: context
        )
        // start/resume запускают автономный цикл: полный промпт цели уходит
        // в чат через обычный send-путь (обработчик apiSendRequested), чтобы
        // модель получила его с полным контекстом, как от юзера.
        if case .start = command,
           let active = outcome.goals.first(where: { $0.state == .active }) {
            _ = GoalLauncher.launch(
                goalID: active.id,
                homeDirectory: Self.homeDirectory,
                language: appState.appLanguage,
                fallbackChatID: context.chatID
            )
        }
        return ["reply": outcome.reply, "goals": outcome.goals.map(goalRow)]
    }

    func goalContext(appState: AppState, params: [String: Any] = [:]) -> GoalContext {
        let session = appState.selectedSession
        var context = GoalContextLogic.context(
            chatID: session?.id,
            sessionDirectory: session?.directory,
            selectedWorkspacePath: appState.selectedWorkspace?.path
        )
        if let chatID = params["chatID"] as? String {
            let trimmed = chatID.trimmingCharacters(in: .whitespacesAndNewlines)
            context.chatID = trimmed.isEmpty ? nil : trimmed
        }
        if let projectPath = params["projectPath"] as? String {
            let trimmed = projectPath.trimmingCharacters(in: .whitespacesAndNewlines)
            context.projectPath = trimmed.isEmpty ? nil : trimmed
        }
        return context
    }

    func goalState(appState: AppState, params: [String: Any] = [:]) -> [String: Any] {
        let goals = GoalContextLogic.visibleGoals(
            GoalStore.load(homeDirectory: Self.homeDirectory),
            context: goalContext(appState: appState, params: params)
        )
        let active = goals.first(where: { $0.state == .active })
        return [
            "goals": goals.map(goalRow),
            "activeGoalId": active?.id.uuidString ?? NSNull()
        ]
    }

    func goalRow(_ goal: UserGoal) -> [String: Any] {
        [
            "id": goal.id.uuidString,
            "title": goal.title,
            "state": goal.state.rawValue,
            "planCount": goal.plan.count,
            "doneCount": goal.plan.filter { $0.status == .done }.count,
            "plan": goal.plan.map { ["title": $0.title, "status": $0.status.rawValue] },
            "createdAt": goal.createdAt.timeIntervalSince1970,
            "updatedAt": goal.updatedAt.timeIntervalSince1970,
            "chatID": goal.chatID ?? NSNull(),
            "projectPath": goal.projectPath ?? NSNull()
        ]
    }

    /// `ui.screenshot`: mirrors the «Скриншоты» menu — the same capture that a
    /// user can trigger from the interface, never an API-only operation.
    func screenshot(params: [String: Any]) throws -> [String: Any] {
        if let rawPath = params["path"] as? String, !rawPath.isEmpty {
            guard let shot = AppWindowCapture.capture() else {
                throw AppActionError.failed("capture failed: no visible window content")
            }
            let url = URL(fileURLWithPath: (rawPath as NSString).expandingTildeInPath)
            try AppWindowCapture.write(shot, to: url)
            return ["ok": true, "path": url.path, "method": shot.method,
                    "width": shot.width, "height": shot.height, "windowTitle": shot.windowTitle]
        }
        let info = try ScreenshotsStore.captureAndSave()
        return ["ok": true, "path": info.path, "method": info.method,
                "width": info.width, "height": info.height, "windowTitle": info.windowTitle]
    }

    /// `goal.verify`: runs the same devil's-advocate verification the post-turn
    /// hook uses, on the active goal, and returns the verdict + continuation.
    func verifyGoal(answer: String,
                    appState: AppState,
                    params: [String: Any] = [:]) async throws -> [String: Any] {
        let goals = GoalContextLogic.visibleGoals(
            GoalStore.load(homeDirectory: Self.homeDirectory),
            context: goalContext(appState: appState, params: params)
        )
        guard let goal = goals.first(where: { $0.state == .active }) else {
            throw AppActionError.notFound("active goal")
        }
        let service = GoalVerificationService { system, user in
            try await InternalModelRunner.complete(messages: [
                DirectChatMessage(role: "system", content: system),
                DirectChatMessage(role: "user", content: user),
            ])
        }
        let outcome = await service.verify(
            goal: goal, lastAssistantText: answer, language: appState.appLanguage)
        return [
            "goalId": goal.id.uuidString,
            "title": goal.title,
            "complete": outcome.verdict.complete,
            "notDone": outcome.verdict.notDone,
            "reason": outcome.verdict.reason,
            "continuation": outcome.continuation ?? NSNull()
        ]
    }
}
