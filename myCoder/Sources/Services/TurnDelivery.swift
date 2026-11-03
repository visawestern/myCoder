import Foundation

/// Text-only transports carry the same per-turn instruction as role-based APIs.
enum TurnDelivery {
    static let projectWorkflow = "Project workflow: inspect contracts and graph dependencies; write a failing test first; update the mechanism, callers, UI/settings, persistence and tests; remove obsolete flows only with evidence; verify behavior and state remaining gaps."

    static func systemInstruction(route: SendRoute, userRules: String, projectRoot: String,
                                  isProject: Bool, agentMode: AgentMode) -> String {
        let rules = [userRules, isProject ? projectWorkflow : ""].filter { !$0.isEmpty }.joined(separator: "\n\n")
        let base: String
        switch route {
        case .openAICompatible, .web:
            base = WebToolProtocolEmulator.systemPreamble(userSystemPrompt: rules, projectRoot: projectRoot,
                isGitRepo: (try? GitRepository.repositoryRoot(for: projectRoot)) != nil)
                + "\n\n" + ToolInstructionGuide.build()
        default:
            base = """
            You are myCoder's assistant. The runtime provides native tools and their argument schemas.
            Use the native tool interface; textual tool fences are not executed by this transport.
            Only claim actions after their tool results. Respect tool permissions and report evidence and remaining gaps.
            cwd: \(projectRoot)
            \(rules)
            """
        }
        return PlanModePromptBuilder.resolve(agentMode: agentMode, baseSystemPrompt: base)
    }

    static func embedded(system: String, context: String, request: String) -> String {
        TurnPresentation.payload(system: system, context: context, request: request)
    }

    static func withSystem(_ system: String, modelText: String) -> String {
        guard !system.isEmpty else { return modelText }
        return "## Системная инструкция\n\(system)\n\n\(modelText)"
    }
}
