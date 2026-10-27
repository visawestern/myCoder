import Foundation

/// The state of one task, distilled from the conversation instead of resending
/// it. It keeps the goal, constraints verbatim, decisions, entities, artifacts,
/// open questions and which source messages each fact came from.
///
/// The ledger is deterministic and append-only: a later build merges into the
/// previous one, so pruning old messages from the visible feed cannot forget a
/// constraint the user stated earlier.
struct TaskLedger: Codable, Equatable, Sendable {
    let sessionID: String
    var projectPath: String
    var goal: String?
    var constraints: [String]
    var decisions: [String]
    var entities: [String]
    var artifacts: [String]
    var openQuestions: [String]
    /// Message ids that contributed at least one field.
    var coverage: [String]
    /// Every message id the ledger was built from.
    var sourceMessageIDs: [String]
    var updatedAt: Int64

    var isEmpty: Bool {
        goal?.isEmpty ?? true
            && constraints.isEmpty && decisions.isEmpty && entities.isEmpty
            && artifacts.isEmpty && openQuestions.isEmpty
    }

    /// Stable text used by the context pack. Constraints and decisions stay
    /// verbatim; nothing is silently shortened.
    var summaryText: String {
        var lines: [String] = []
        if let goal, !goal.isEmpty {
            lines.append("- Цель: \(goal)")
        }
        if !constraints.isEmpty {
            lines.append("- Ограничения (дословно):")
            lines.append(contentsOf: constraints.map { "  - \($0)" })
        }
        if !decisions.isEmpty {
            lines.append("- Решения:")
            lines.append(contentsOf: decisions.map { "  - \($0)" })
        }
        if !entities.isEmpty {
            lines.append("- Сущности: \(entities.joined(separator: ", "))")
        }
        if !artifacts.isEmpty {
            lines.append("- Артефакты: \(artifacts.joined(separator: ", "))")
        }
        if !openQuestions.isEmpty {
            lines.append("- Открытые вопросы:")
            lines.append(contentsOf: openQuestions.map { "  - \($0)" })
        }
        if !coverage.isEmpty {
            lines.append("- Покрытие: \(coverage.count) сообщений, \(artifacts.count) файлов")
        }
        return lines.joined(separator: "\n")
    }
}

enum TaskLedgerExtraction {

    /// Cues are matched case-insensitively against the whole message; the
    /// message is stored verbatim, never reworded.
    private static let constraintCues = [
        "must", "must not", "never", "always", "constraint",
        "нельзя", "обязательн", "должен", "должна", "не трогай",
        "не ломай", "только "
    ]
    private static let decisionCues = [
        "decision:", "решение:", "решили", "we decided", "будем использ",
        "выбрали"
    ]

    static func build(sessionID: String,
                      projectPath: String,
                      goal: String?,
                      messages: [Message],
                      memories: [ProjectMemoryChunk] = [],
                      previous: TaskLedger? = nil,
                      now: Int64 = Int64(Date().timeIntervalSince1970)) -> TaskLedger {
        var constraints: [String] = previous?.constraints ?? []
        var decisions: [String] = previous?.decisions ?? []
        var entities: [String] = previous?.entities ?? []
        var artifacts: [String] = previous?.artifacts ?? []
        var openQuestions: [String] = previous?.openQuestions ?? []
        var coverage: [String] = previous?.coverage ?? []
        var sourceIDs: [String] = previous?.sourceMessageIDs ?? []

        func add(_ value: String, to list: inout [String]) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !list.contains(trimmed) else { return }
            list.append(trimmed)
        }

        func markCovered(_ id: String) {
            add(id, to: &coverage)
        }

        let resolvedGoal: String? = {
            if let goal = goal?.trimmingCharacters(in: .whitespacesAndNewlines), !goal.isEmpty {
                return goal
            }
            if let previousGoal = previous?.goal, !previousGoal.isEmpty { return previousGoal }
            return messages.first { $0.role == .user }?
                .content.trimmingCharacters(in: .whitespacesAndNewlines)
        }()

        for memory in memories where memory.kind == "decision" {
            add(memory.text, to: &decisions)
            if let id = memory.sourceMessageID, !id.isEmpty {
                markCovered(id)
                add(id, to: &sourceIDs)
            }
        }

        for message in messages {
            add(message.id, to: &sourceIDs)
            switch message.role {
            case .system:
                continue
            case .user, .assistant:
                break
            }

            let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let lower = text.lowercased()
            var contributed = false

            if message.role == .user,
               constraintCues.contains(where: { lower.contains($0) }) {
                add(text, to: &constraints)
                contributed = true
            }
            if decisionCues.contains(where: { lower.contains($0) }) {
                add(text, to: &decisions)
                contributed = true
            }
            if message.role == .user {
                let plan = ContextQueryPlanner.plan(for: text)
                for symbol in plan.symbols {
                    add(symbol, to: &entities)
                    contributed = true
                }
                for file in plan.files where isConcreteArtifact(file) {
                    add(file, to: &artifacts)
                    contributed = true
                }
                for line in text.split(separator: "\n") {
                    let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedLine.contains("?") || trimmedLine.lowercased().hasPrefix("todo") {
                        add(trimmedLine, to: &openQuestions)
                        contributed = true
                    }
                }
            }
            if contributed { markCovered(message.id) }
        }

        return TaskLedger(
            sessionID: sessionID,
            projectPath: projectPath,
            goal: resolvedGoal?.isEmpty == false ? resolvedGoal : previous?.goal,
            constraints: constraints,
            decisions: decisions,
            entities: entities,
            artifacts: artifacts,
            openQuestions: openQuestions,
            coverage: coverage,
            sourceMessageIDs: sourceIDs,
            updatedAt: now
        )
    }

    /// A path mentioned by the user is an artifact, but only if it could be a
    /// project-relative file. `..` and absolute paths are not recorded.
    private static func isConcreteArtifact(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/") else { return false }
        return !path.split(separator: "/").contains("..")
    }
}

/// Policy for using the ledger in place of the raw transcript.
enum TaskLedgerPolicy {

    /// Short conversations still carry useful immediacy, so the raw turns are
    /// kept. Once the history is long, the ledger plus the current request and
    /// the evidence is what the model receives instead of twenty messages.
    static let minimumTurnsToReplace = 6

    static func replacesRawHistory(summary: String?, priorTurnCount: Int) -> Bool {
        guard let summary, !summary.isEmpty else { return false }
        return priorTurnCount >= minimumTurnsToReplace
    }
}
