import Foundation

/// Text-only transports carry the same per-turn instruction as role-based APIs.
enum TurnDelivery {
    static let projectWorkflow = "Project workflow: inspect contracts and graph dependencies; write a failing test first; update the mechanism, callers, UI/settings, persistence and tests; remove obsolete flows only with evidence; verify behavior and state remaining gaps."

    static func systemInstruction(route: SendRoute, userRules: String, projectRoot: String,
                                  isProject: Bool, agentMode: AgentMode,
                                  profile: HarnessProfile? = nil,
                                  homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        let rules = [userRules, isProject ? projectWorkflow : ""].filter { !$0.isEmpty }.joined(separator: "\n\n")
        let skillIDs = AgentResourcesLoader.loadSkills(homeDirectory: homeDirectory).map(\.id)
        let mcpServerIDs = AgentResourcesLoader.loadMCPServers(homeDirectory: homeDirectory)
            .filter(\.isEnabled).map(\.id)
        let base: String
        switch route {
        case .openAICompatible, .web:
            let tools = profile?.tools ?? WebEmulatedTool.allCases
            let allowed = tools.filter {
                PlanModeToolPolicy.decision(
                    for: WebToolCall(name: $0.rawValue, arguments: [:]), mode: agentMode
                ) == .execute
            }
            base = WebToolProtocolEmulator.systemPreamble(tools: allowed, userSystemPrompt: rules, projectRoot: projectRoot,
                isGitRepo: (try? GitRepository.repositoryRoot(for: projectRoot)) != nil)
                + "\n\n" + ToolInstructionGuide.build(
                    tools: tools, agentMode: agentMode,
                    skillIDs: skillIDs, mcpServerIDs: mcpServerIDs
                )
                // Fable-style conduct on one line: the full block would push
                // emulated web pastes over vendor budgets (Kimi ~4000B).
                + "\n\n" + HarnessPromptQuality.compactConductLine
                // The 0.1 uncertainty contract must reach web routes too.
                + "\n\n" + HarnessPromptQuality.compactUncertaintyLine
        default:
            // Blended: OpenCode-style collaboration core + Claude Code evidence
            // discipline, on top of the native tool contract.
            base = """
            \(HarnessPromptQuality.collaborationCore)

            \(HarnessPromptQuality.humanProblemSolvingGuidance)

            The runtime provides native tools and their argument schemas. Use the
            native tool interface; textual tool fences are not executed by this transport.
            Never claim a tool ran or a file changed before you see its result.
            Only claim actions after their tool results. Respect tool permissions and
            report evidence and remaining gaps.
            cwd: \(projectRoot)

            \(ToolCatalogSnapshot(
                tools: [], agentMode: agentMode,
                skillIDs: skillIDs, mcpServerIDs: mcpServerIDs
            ).text)

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
