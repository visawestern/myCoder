import Foundation

/// One atomic task of the current execution plan, in the shape the todo
/// tools expose to the model.
struct PlanTodoItem: Equatable {
    /// Stable key of the plan node (`T1`, `T2`, …) — the id a model uses to
    /// address the task in `todo_update` / `task_update`.
    let id: String
    let title: String
    /// Raw plan status (pending/running/done/failed/blocked/skipped).
    let status: String
    /// Status in the todo vocabulary (pending/in_progress/completed).
    let todoStatus: String
    /// Keys of the tasks this one depends on.
    let dependsOn: [String]
    /// Acceptance criteria of the task (what "done" means).
    let acceptanceCriteria: [String]
    /// True for the task that is currently being executed.
    let isActive: Bool
}

/// Bridges the execution plan (the spec decomposition) into the todo tools.
///
/// User directive: the current plan must be visible to the assistant through
/// `todo_read` — the same alias OpenCode uses for its checklist — and the
/// granular `todo_edit` / `todo_update` tools must be able to move a plan
/// item. The plan is the source of truth; the session checklist stays a
/// scratch pad next to it.
enum PlanTodoBridge {
    /// Plan status → todo status.
    static func todoStatus(for status: String) -> String {
        switch status.lowercased() {
        case "done", "completed", "skipped":
            return "completed"
        case "running", "in_progress", "in-progress":
            return "in_progress"
        default:
            return "pending"
        }
    }

    /// The active plan of a project: the latest spec revision that has nodes.
    /// Empty when the project has no plan yet.
    static func planItems(projectPath: String) -> [PlanTodoItem] {
        guard let database = try? ProjectDatabaseManager.manager(forProjectPath: projectPath) else {
            return []
        }
        let store = database.makeSpecStore()
        let projectID = ProjectIdentityLogic.projectID(for: projectPath)
        guard let revision = try? store.latestRevision(projectID: projectID) else { return [] }
        let nodes = (try? store.nodes(revisionID: revision.id)) ?? []
        guard !nodes.isEmpty else { return [] }
        let edges = (try? store.edges(revisionID: revision.id)) ?? []

        var externalKeyByNodeID: [String: String] = [:]
        for node in nodes {
            externalKeyByNodeID[node.id] = node.externalKey
        }
        // Edges are stored dependent → dependency.
        var dependencies: [String: [String]] = [:]
        for edge in edges where edge.kind == "depends_on" {
            let dependencyKey = externalKeyByNodeID[edge.toNodeID] ?? edge.toNodeID
            dependencies[edge.fromNodeID, default: []].append(dependencyKey)
        }
        let activeNodeID = nodes.first(where: { $0.status == "running" })?.id

        return nodes.map { node in
            PlanTodoItem(
                id: node.externalKey,
                title: node.title,
                status: node.status,
                todoStatus: todoStatus(for: node.status),
                dependsOn: (dependencies[node.id] ?? []).sorted(),
                acceptanceCriteria: SpecNodeExecutionLogic.acceptanceCriteria(of: node),
                isActive: node.id == activeNodeID
            )
        }
    }

    /// One plan line: status, key, title, dependencies, acceptance criteria.
    static func planLine(for item: PlanTodoItem) -> String {
        var parts: [String] = []
        if item.isActive {
            parts.append("active")
        }
        if item.todoStatus != item.status {
            parts.append("todo: \(item.todoStatus)")
        }
        if !item.dependsOn.isEmpty {
            parts.append("depends on: \(item.dependsOn.joined(separator: ", "))")
        }
        let criteria = item.acceptanceCriteria.prefix(3)
            .map { criterion -> String in
                let single = criterion.trimmingCharacters(in: .whitespacesAndNewlines)
                return single.count > 120 ? String(single.prefix(120)) + "…" : single
            }
        if !criteria.isEmpty {
            parts.append("criteria: " + criteria.joined(separator: " | "))
        }
        let suffix = parts.isEmpty ? "" : " — " + parts.joined(separator: "; ")
        return "[\(item.status)] \(item.id): \(item.title)\(suffix)"
    }

    /// The text `todo_read` returns: the execution plan first (it is the
    /// authoritative checklist), the session checklist second.
    static func mergedText(sessionTodos: [[String: Any]], planItems: [PlanTodoItem]) -> String {
        var sections: [String] = []

        if !planItems.isEmpty {
            let planLines = planItems.map { planLine(for: $0) }
            sections.append("## Execution plan\n" + planLines.joined(separator: "\n"))
        }

        if !sessionTodos.isEmpty {
            let planIDs = Set(planItems.map(\.id))
            // A checklist item that repeats a plan task id is shown once —
            // in the plan section — so the model never counts it twice.
            let todoLines = sessionTodos
                .filter { item in
                    guard let id = item["id"] as? String else { return true }
                    return !planIDs.contains(id)
                }
                .map { item -> String in
                    let id = item["id"] as? String ?? "?"
                    let content = item["content"] as? String ?? ""
                    let status = item["status"] as? String ?? "pending"
                    return "[\(status)] \(id): \(content)"
                }
            if !todoLines.isEmpty {
                sections.append("## Session checklist\n" + todoLines.joined(separator: "\n"))
            }
        }

        guard !sections.isEmpty else { return "[]" }
        return sections.joined(separator: "\n\n")
    }
}
