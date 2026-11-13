import Foundation
import CryptoKit

/// Immutable per-turn description of the host capabilities. It is rebuilt from
/// current resources on every send; no cross-turn cache can hide a changed mode,
/// profile, installed skill or MCP configuration.
struct ToolCatalogSnapshot {
    let tools: [WebEmulatedTool]
    let agentMode: AgentMode
    let skillIDs: [String]
    let mcpServerIDs: [String]

    /// Stable identity of the effective catalog. Input order is intentionally
    /// ignored: the same capabilities must produce the same revision.
    var revision: String {
        let canonical = [
            agentMode.rawValue,
            tools.map(\.rawValue).sorted().joined(separator: ","),
            skillIDs.sorted().joined(separator: ","),
            mcpServerIDs.sorted().joined(separator: ",")
        ].joined(separator: "|")
        return SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }.joined().prefix(12).description
    }

    /// Compact resource lines added to the prompt. Inputs are real installed
    /// names; output never claims that an MCP exposes a particular tool schema.
    var text: String {
        var lines = ["Catalog revision: \(revision)", "Mode: \(agentMode.rawValue)"]
        if !skillIDs.isEmpty {
            lines.append("Installed skills: \(skillIDs.sorted().joined(separator: ", ")). Use the skill tool to list or read their current instructions; do not assume they execute automatically.")
        }
        if !mcpServerIDs.isEmpty {
            lines.append("Installed MCP servers: \(mcpServerIDs.sorted().joined(separator: ", ")). These are configured resources, not emulated tool declarations; use only schemas actually supplied by the runtime and report connection errors.")
        }
        return lines.joined(separator: "\n")
    }
}

extension ToolInstructionGuide {
    /// Builds the detailed guide from the effective, mode-filtered tool set.
    /// Inputs are the selected profile/mode and actual resources; output is a
    /// fresh per-turn contract. Depends on WebEmulatedTool schemas and loaders.
    static func build(tools: [WebEmulatedTool] = WebEmulatedTool.allCases,
                      agentMode: AgentMode = .build,
                      skillIDs: [String] = [],
                      mcpServerIDs: [String] = []) -> String {
        let allowed = tools.filter {
            PlanModeToolPolicy.decision(
                for: WebToolCall(name: $0.rawValue, arguments: [:]),
                mode: agentMode
            ) == .execute
        }
        let snapshot = ToolCatalogSnapshot(
            tools: allowed, agentMode: agentMode,
            skillIDs: skillIDs, mcpServerIDs: mcpServerIDs
        )
        let listed = Set(allowed.map(\.rawValue))
        let onRequest = WebEmulatedTool.allCases
            .filter { !listed.contains($0.rawValue) }
            .map(\.rawValue).joined(separator: ", ")
        let protocolGuide = """
        \(snapshot.text)
        Tool mini guide:
        Only tools listed below are in this turn's emulated contract. Mode and host permissions still apply at execution time.
        Invoke a tool with a JSON object in a tool fence, then wait for the host's tool_result before deciding the next action:
        ```tool
        {"name": "read_file", "args": {"path": "Sources/Store.swift", "offset": "1", "limit": "80"}}
        ```
        Never report success before receiving the corresponding tool_result. Read errors, approval requests and truncation notices as execution outcomes; do not invent missing output or retry a mutating call blindly.
        Schemas below describe parameter names and meanings; angle-bracket values are placeholders. Omit optional parameters rather than sending placeholder text. Paths are relative to the configured working directory unless an absolute path is supplied; host validation still applies.
        Host permissions: at askBeforeChanges, file writes, checklist mutations, Git mutations and sub-agent requests require approval. At editAutomatically, every file edit and the whole todo/task checklist run without approval inside the project folder; a path outside the project folder asks the user first. Read-only tools and recognized read-only shell commands are allowed by the current gate. Other run_command calls require approval below fullAccess. Permission does not guarantee that a provider, browser session, skill, repository or external service is configured.
        """
        var parts = [protocolGuide]
        // M1/refactor: the canonical coding-discipline contract rides EVERY
        // emulated route too, so web / OpenAI-compatible transports enforce the
        // exact same TDD / ≤600-line / function-contract / modularity rules as
        // the native route (single source: `HarnessPromptQuality.codeDiscipline`).
        parts.append(HarnessPromptQuality.codeDiscipline)
        if agentMode == .build || agentMode == .plan {
            parts.append(HarnessPromptQuality.todoWorkflow)
        }
        if !onRequest.isEmpty {
            parts.append("Not in this profile/mode (available on request only if host policy changes): \(onRequest)")
        }
        parts.append(contentsOf: allowed.map { tool in
            "### \(tool.rawValue)\n\(tool.description)\nArguments: \(tool.argumentSchema)\n\(notes(for: tool))"
        })
        return parts.joined(separator: "\n\n")
    }
}
