import Foundation

/// Pure execution rules for a spec decomposition. The store used to ask the
/// planner-side decomposition model, which only knew whether a dependency was
/// `done`; that let a `running` node be started twice and made `skipped`
/// dependencies block their dependents forever.
enum SpecNodeExecutionLogic {
    static let completedStatuses: Set<String> = ["done", "skipped"]
    static let runnableStatuses: Set<String> = ["pending"]

    /// Strictly one task at a time: a running task hides every other task.
    /// Only pending nodes are eligible; failed/blocked/skipped nodes require an
    /// explicit retry or a manual status change first. A dependency counts as
    /// satisfied when it is done or deliberately skipped.
    static func nextRunnableNode(nodes: [ProjectSpecNode],
                                 edges: [ProjectSpecEdge]) -> ProjectSpecNode? {
        guard !nodes.contains(where: { $0.status == "running" }) else { return nil }

        let completed = Set(
            nodes.filter { completedStatuses.contains($0.status) }.map(\.id)
        )
        var dependencies: [String: Set<String>] = [:]
        for edge in edges where edge.kind == "depends_on" {
            dependencies[edge.fromNodeID, default: []].insert(edge.toNodeID)
        }

        return nodes
            .filter { runnableStatuses.contains($0.status) }
            .filter { node in
                dependencies[node.id, default: []].allSatisfy(completed.contains)
            }
            .sorted { lhs, rhs in
                lhs.sortOrder == rhs.sortOrder
                    ? lhs.externalKey < rhs.externalKey
                    : lhs.sortOrder < rhs.sortOrder
            }
            .first
    }

    static func canStart(nodeID: String,
                         nodes: [ProjectSpecNode],
                         edges: [ProjectSpecEdge]) -> Bool {
        nextRunnableNode(nodes: nodes, edges: edges)?.id == nodeID
    }

    static func codingPrompt(node: ProjectSpecNode,
                             specification: String,
                             projectPath: String) -> String {
        let criteria = acceptanceCriteria(of: node)
        let criteriaText = criteria.isEmpty
            ? "- (no acceptance criteria recorded)"
            : criteria.map { "- \($0)" }.joined(separator: "\n")
        let spec = specification.trimmingCharacters(in: .whitespacesAndNewlines)
        let specText = spec.isEmpty ? "(specification text is unavailable)" : spec

        return """
        You are implementing one task from an approved project specification.

        Project directory: \(projectPath)
        Task: \(node.externalKey) · \(node.title)
        Kind: \(node.kind)
        Description:
        \(node.description)

        Acceptance criteria:
        \(criteriaText)

        Approved specification:
        \(specText)

        Rules:
        - Implement only this task; do not start other tasks.
        - Follow the approved specification and the project's existing conventions.
        - Run the relevant build and tests, and report the exact commands and results.
        - Do not claim the task is complete without evidence; report what changed and what remains.
        """
    }

    static func acceptanceCriteria(of node: ProjectSpecNode) -> [String] {
        guard let raw = node.acceptanceCriteriaJSON,
              let data = raw.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return values
    }
}
