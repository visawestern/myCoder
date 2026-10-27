import Foundation

/// Orchestrates one local compilation: project board → local model → validated
/// atomic task. Everything here runs on the user's machine and is free.
struct LocalTaskCompilerService {
    struct CompiledTask: Equatable {
        let task: AtomicTask
        /// The local model that produced the task.
        let model: String
    }

    let board: ContextBoard
    let runner: LocalModelRunner

    func compile(userRequest: String, planNode: PlanTodoItem?) async throws -> CompiledTask {
        let prompt = LocalCompilerPromptBuilder.build(
            userRequest: userRequest,
            board: board,
            planNode: planNode
        )
        let outcome = try await runner.run(prompt: prompt.user, system: prompt.system)
        let task = try AtomicTaskParser.parse(outcome.text)
        try Self.validate(task: task, board: board)
        return CompiledTask(task: task, model: outcome.candidate.model)
    }

    /// The local model must point at files that really exist in the project.
    /// A wrong path is an error, not something we silently drop (D4).
    static func validate(task: AtomicTask, board: ContextBoard) throws {
        let known = Set(board.entries.map(\.path))
        for reference in task.refs where !known.contains(reference.path) {
            throw LocalCompilerError.unknownReference(path: reference.path)
        }
    }
}
