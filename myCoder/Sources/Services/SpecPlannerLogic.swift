import Foundation

// MARK: - Shared parsing

enum SpecPlannerParseError: Error, Equatable, LocalizedError {
    case missingJSONObject
    case invalidJSON(String)

    var errorDescription: String? {
        switch self {
        case .missingJSONObject:
            return "The planner response does not contain a JSON object"
        case .invalidJSON(let detail):
            return "The planner response is not valid JSON: \(detail)"
        }
    }
}

enum SpecPlannerJSON {
    /// Models often wrap JSON in prose or a markdown fence. Extract the
    /// outermost object instead of requiring a bare response, but never try to
    /// repair malformed JSON: a silent guess here would corrupt the spec.
    static func objectData(from raw: String) throws -> Data {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}"),
              start <= end else {
            throw SpecPlannerParseError.missingJSONObject
        }
        let json = String(trimmed[start...end])
        guard let data = json.data(using: .utf8) else {
            throw SpecPlannerParseError.missingJSONObject
        }
        return data
    }

    static func decode<T: Decodable>(_ type: T.Type, from raw: String) throws -> T {
        let data = try objectData(from: raw)
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw SpecPlannerParseError.invalidJSON(error.localizedDescription)
        }
    }

    static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedList(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let clean = trimmed(value)
            guard !clean.isEmpty, seen.insert(clean).inserted else { continue }
            result.append(clean)
        }
        return result
    }
}

// MARK: - Interview

struct SpecInterviewQuestion: Codable, Equatable {
    var id: String
    var question: String
    var suggestedAnswers: [String]
    var done: Bool
    var summary: String?
    /// How much of the task is still unclear (0 = fully understood, 1 = no
    /// idea). The planner must keep asking while this is above
    /// `SpecInterviewLogic.uncertaintyThreshold`. Absent in older turns.
    var uncertainty: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case question
        case suggestedAnswers = "suggested_answers"
        case done
        case summary
        case uncertainty
    }

    init(id: String,
         question: String,
         suggestedAnswers: [String] = [],
         done: Bool = false,
         summary: String? = nil,
         uncertainty: Double? = nil) {
        self.id = id
        self.question = question
        self.suggestedAnswers = suggestedAnswers
        self.done = done
        self.summary = summary
        self.uncertainty = uncertainty
    }
}

extension SpecInterviewQuestion {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        question = try container.decodeIfPresent(String.self, forKey: .question) ?? ""
        suggestedAnswers = try container.decodeIfPresent([String].self, forKey: .suggestedAnswers) ?? []
        done = try container.decodeIfPresent(Bool.self, forKey: .done) ?? false
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        uncertainty = try container.decodeIfPresent(Double.self, forKey: .uncertainty)
    }
}

enum SpecInterviewLogic {
    /// The interview stops only when the planner's own uncertainty about the
    /// task drops below this value. The host enforces it: `done:true` above the
    /// threshold is bounced back with "ask the next question".
    static let uncertaintyThreshold = 0.1

    /// How many times a planner that answers `done` while still uncertain is
    /// sent back for the decisive question. Two extra asks are enough for a
    /// cooperating model and cannot spin the loop forever; after the budget a
    /// stubborn `done` is accepted and the user can still use Clarify.
    static let maxUncertaintyRetries = 2

    static func needsMoreQuestions(_ question: SpecInterviewQuestion) -> Bool {
        guard question.done else { return false }
        guard let uncertainty = question.uncertainty else { return false }
        return uncertainty > uncertaintyThreshold
    }


    /// Validates the planner turn. A finished interview may omit the question
    /// text; an unfinished one must carry both a stable id and a question.
    static func decode(_ raw: String) throws -> SpecInterviewQuestion {
        var question = try SpecPlannerJSON.decode(SpecInterviewQuestion.self, from: raw)
        question.id = SpecPlannerJSON.trimmed(question.id)
        question.question = SpecPlannerJSON.trimmed(question.question)
        question.suggestedAnswers = SpecPlannerJSON.normalizedList(question.suggestedAnswers)
        question.summary = question.summary.map(SpecPlannerJSON.trimmed).flatMap { $0.isEmpty ? nil : $0 }

        if !question.done {
            guard !question.id.isEmpty else {
                throw SpecPlannerParseError.invalidJSON("interview question has no id")
            }
            guard !question.question.isEmpty else {
                throw SpecPlannerParseError.invalidJSON("interview question has no text")
            }
        }
        return question
    }
}

// MARK: - Atomic decomposition

struct SpecDecompositionNode: Equatable, Identifiable {
    let key: String
    let title: String
    let description: String
    let kind: String
    let acceptanceCriteria: [String]
    let dependsOn: [String]
    let order: Int

    var id: String { key }
}

struct SpecDecomposition: Equatable {
    let nodes: [SpecDecompositionNode]

    var nodeCount: Int { nodes.count }

    /// Strictly one node at a time: the first uncompleted node whose
    /// dependencies are all done, ordered by the planner's stable order.
    func nextNode(completed: Set<String>) -> SpecDecompositionNode? {
        nodes
            .filter { node in
                !completed.contains(node.key)
                    && node.dependsOn.allSatisfy(completed.contains)
            }
            .sorted { lhs, rhs in
                lhs.order == rhs.order ? lhs.key < rhs.key : lhs.order < rhs.order
            }
            .first
    }
}

enum SpecDecompositionError: Error, Equatable, LocalizedError {
    case empty
    case emptyKey
    case duplicateKey(String)
    case emptyTitle(String)
    case emptyDescription(String)
    case missingAcceptance(String)
    case missingDependency(node: String, dependency: String)
    case selfDependency(String)
    case cycle([String])

    var errorDescription: String? {
        switch self {
        case .empty:
            return "The decomposition contains no nodes"
        case .emptyKey:
            return "Every decomposition node needs a key"
        case .duplicateKey(let key):
            return "Duplicate decomposition key: \(key)"
        case .emptyTitle(let key):
            return "Node \(key) has no title"
        case .emptyDescription(let key):
            return "Node \(key) has no description"
        case .missingAcceptance(let key):
            return "Node \(key) has no acceptance criteria"
        case .missingDependency(let node, let dependency):
            return "Node \(node) depends on unknown node \(dependency)"
        case .selfDependency(let key):
            return "Node \(key) depends on itself"
        case .cycle(let keys):
            return "Decomposition cycle between nodes: \(keys.joined(separator: ", "))"
        }
    }
}

enum SpecDecompositionLogic {
    private struct Payload: Decodable {
        let nodes: [RawNode]
    }

    private struct RawNode: Decodable {
        let key: String
        let title: String
        let description: String
        let kind: String?
        let acceptanceCriteria: [String]?
        let dependsOn: [String]?
        let order: Int?

        private enum CodingKeys: String, CodingKey {
            case key
            case title
            case description
            case kind
            case acceptanceCriteria = "acceptance_criteria"
            case acceptanceCriteriaCamel = "acceptanceCriteria"
            case dependsOn = "depends_on"
            case dependsOnCamel = "dependsOn"
            case order
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            key = try container.decodeIfPresent(String.self, forKey: .key) ?? ""
            title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
            description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
            kind = try container.decodeIfPresent(String.self, forKey: .kind)
            acceptanceCriteria = try container.decodeIfPresent([String].self, forKey: .acceptanceCriteria)
                ?? container.decodeIfPresent([String].self, forKey: .acceptanceCriteriaCamel)
            dependsOn = try container.decodeIfPresent([String].self, forKey: .dependsOn)
                ?? container.decodeIfPresent([String].self, forKey: .dependsOnCamel)
            order = try container.decodeIfPresent(Int.self, forKey: .order)
        }
    }

    /// Decodes, normalizes and validates the planner decomposition. Nothing is
    /// persisted when validation fails, so a bad model answer can never become
    /// executable work.
    static func decode(_ raw: String) throws -> SpecDecomposition {
        let payload = try SpecPlannerJSON.decode(Payload.self, from: raw)
        guard !payload.nodes.isEmpty else { throw SpecDecompositionError.empty }

        var nodes: [SpecDecompositionNode] = []
        var seen = Set<String>()
        for (index, rawNode) in payload.nodes.enumerated() {
            let key = SpecPlannerJSON.trimmed(rawNode.key)
            guard !key.isEmpty else { throw SpecDecompositionError.emptyKey }
            guard seen.insert(key).inserted else {
                throw SpecDecompositionError.duplicateKey(key)
            }
            let title = SpecPlannerJSON.trimmed(rawNode.title)
            guard !title.isEmpty else { throw SpecDecompositionError.emptyTitle(key) }
            let description = SpecPlannerJSON.trimmed(rawNode.description)
            guard !description.isEmpty else {
                throw SpecDecompositionError.emptyDescription(key)
            }
            let acceptance = SpecPlannerJSON.normalizedList(rawNode.acceptanceCriteria ?? [])
            guard !acceptance.isEmpty else {
                throw SpecDecompositionError.missingAcceptance(key)
            }
            let dependsOn = SpecPlannerJSON.normalizedList(rawNode.dependsOn ?? [])
            guard !dependsOn.contains(key) else {
                throw SpecDecompositionError.selfDependency(key)
            }
            let kind = SpecPlannerJSON.trimmed(rawNode.kind ?? "task")
            nodes.append(SpecDecompositionNode(
                key: key,
                title: title,
                description: description,
                kind: kind.isEmpty ? "task" : kind,
                acceptanceCriteria: acceptance,
                dependsOn: dependsOn,
                order: rawNode.order ?? index
            ))
        }

        let keys = Set(nodes.map(\.key))
        for node in nodes {
            for dependency in node.dependsOn where !keys.contains(dependency) {
                throw SpecDecompositionError.missingDependency(node: node.key, dependency: dependency)
            }
        }
        try validateAcyclic(nodes)

        nodes.sort { lhs, rhs in
            lhs.order == rhs.order ? lhs.key < rhs.key : lhs.order < rhs.order
        }
        return SpecDecomposition(nodes: nodes)
    }

    private static func validateAcyclic(_ nodes: [SpecDecompositionNode]) throws {
        var indegree = Dictionary(uniqueKeysWithValues: nodes.map { ($0.key, 0) })
        var dependents: [String: [String]] = [:]
        for node in nodes {
            for dependency in node.dependsOn {
                indegree[node.key, default: 0] += 1
                dependents[dependency, default: []].append(node.key)
            }
        }

        var queue = indegree.filter { $0.value == 0 }.map(\.key).sorted()
        var visited: [String] = []
        while !queue.isEmpty {
            let key = queue.removeFirst()
            visited.append(key)
            for dependent in dependents[key, default: []].sorted() {
                indegree[dependent, default: 0] -= 1
                if indegree[dependent] == 0 {
                    queue.append(dependent)
                    queue.sort()
                }
            }
        }

        guard visited.count == nodes.count else {
            let cycle = indegree.filter { $0.value > 0 }.map(\.key).sorted()
            throw SpecDecompositionError.cycle(cycle)
        }
    }
}

// MARK: - Gate and revisions

enum SpecWizardGateLogic {
    /// Chat stays blocked while the project has an unfinished draft. A ready
    /// draft is not blocked even if the completion flag was not persisted yet:
    /// all required artifacts already exist.
    static func shouldBlockChat(_ draft: SpecWizardDraft?) -> Bool {
        guard let draft else { return false }
        return draft.status == .draft && draft.step != .ready
    }
}

enum SpecRevisionLogic {
    static func nextVersion(existing: [Int]) -> Int {
        (existing.max() ?? 0) + 1
    }

    static func isValid(content: String) -> Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
