import Foundation

extension MyCoderAPIServer {
    /// POST /api/context-preview {"message": "..."} — runs the REAL context
    /// pipeline for a message without sending it, and returns exactly what the
    /// model would receive, split into the viewer's tabs. This is the live
    /// verification surface for the context directives (2026-11-03): one curl
    /// proves the stages, the tabs, the system instruction and the harness
    /// questions are actually assembled — no GUI automation needed.
    func handleContextPreview(body: String) async -> String {
        guard await Self.mainRead({ __myCoderAppState != nil }) else {
            return jsonResponse(["error": "app not ready"])
        }
        guard let data = body.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let message = object["message"] as? String,
              !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return jsonResponse(["error": "message is required"])
        }
        // The request body may name the project to preview. Without it,
        // fall back to the currently selected workspace so the preview
        // mirrors what a send would collect (user check 2026-11-08: the
        // preview ignored the passed projectPath and always used the
        // selected workspace).
        let requestedProject = (object["projectPath"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let request = await Self.mainRead { () -> ContextPreviewService.Request in
            let appState = __myCoderAppState!
            let projectPath = requestedProject.isEmpty
                ? (appState.selectedWorkspace?.path ?? "")
                : requestedProject
            let params = ModelCallParametersStore.parameters(for: appState.effectiveSelectedModel())
            let toolRoot = appState.toolWorkingDirectory
            let route = SendRouteResolver.route(
                selectedProviderID: appState.selectedProviderID, selectedModel: appState.effectiveSelectedModel(),
                serverConnected: appState.serverConnected, isACP: appState.isSelectedACPProvider,
                customProviders: appState.customProviders, localProviders: LocalProviderLogic.load(),
                webProviderIDs: appState.webProviderIDs)
            let webRules: String
            if case .web(let id) = route { webRules = WebProviderStore.load().first(where: { $0.id == id })?.systemPrompt ?? "" }
            else { webRules = "" }
            let systemPrompt = TurnDelivery.systemInstruction(route: route,
                userRules: [webRules, params.systemPrompt ?? ""].filter { !$0.isEmpty }.joined(separator: "\n\n"),
                projectRoot: toolRoot, isProject: !projectPath.isEmpty, agentMode: appState.agentMode)
            return ContextPreviewService.Request(
                message: message,
                projectPath: projectPath,
                isEnabled: appState.isPointContextEnabled,
                isPlannerEnabled: appState.isLocalQueryPlannerEnabled,
                systemPrompt: systemPrompt,
                skillsDirectory: MyCoderPaths.skillsDir(
                    homeDirectory: FileManager.default.homeDirectoryForCurrentUser
                ),
                isPlanMode: appState.agentMode == .plan
            )
        }
        var payload = await ContextPreviewService.run(request)
        // Expose the resolved context window for the selected model so a
        // live curl proves which window myCoder actually applies (e.g.
        // Mercury = 1M from opencode.json, not the 200k default).
        // An optional `modelId` in the request body overrides the model
        // used for this read-only window calculation (for live checks
        // when the provider list is empty).
        let windowModel: String = await Self.mainRead {
            let requested = (object["modelId"] as? String) ?? ""
            if !requested.isEmpty { return requested }
            return __myCoderAppState?.effectiveSelectedModel() ?? ""
        }
        payload["contextWindow"] = ContextWindowCatalog.limit(for: windowModel)
        payload["selectedModel"] = windowModel
        return jsonResponse(payload)
    }
}
