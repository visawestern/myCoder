import Foundation

/// Project-less write gate for the real tool executor.
///
/// Input: one tool call requested by the model.
/// Output: nil when the tool may run, or the refusal text when the chat has no
/// project and the tool would change files.
///
/// Purpose: keep the main executor file inside the 600-line module budget
/// while the gate stays a separate, testable unit. The decision itself lives in
/// `ProjectlessWriteLogic`; this extension only adapts a tool call to it and
/// asks the host UI to create a project.
///
/// Dependencies: `ProjectlessWriteLogic`, `WebToolProtocolEmulator`, and the
/// `isProjectless` / `projectlessWritePrompt` properties of the executor.
extension ProjectWebToolExecutor {

    /// Asks the host to create a project when a projectless chat tries to
    /// change a file. Returns the refusal text, or nil when the tool may run.
    func projectlessWriteRefusal(for call: WebToolCall) async -> String? {
        guard isProjectless, ProjectlessWriteLogic.requiresProject(toolName: call.name) else {
            return nil
        }
        let canonical = WebToolProtocolEmulator.canonicalized(call)
        let tool = WebEmulatedTool(rawValue: canonical.name)
        let arguments = tool.map {
            WebToolProtocolEmulator.normalizedArguments(for: $0, from: canonical.arguments)
        } ?? canonical.arguments
        let suggested = ProjectlessWriteLogic.suggestedProjectName(for: arguments["path"] ?? "")
        let created = await projectlessWritePrompt?(suggested)
        return ProjectlessWriteLogic.refusalMessage(createdProjectPath: created)
    }
}
