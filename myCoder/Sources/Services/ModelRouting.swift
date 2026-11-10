import Foundation

/// Independent work kinds whose provider/model can be selected separately.
enum ModelRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case dispatch
    case planning
    case research
    case execution
    case review
    case correction
    case compaction
    case vision
    case finalResponse

    var id: String { rawValue }

    /// Human-readable role name used by the routing picker and execution log.
    var displayName: String {
        switch self {
        case .dispatch: return "Request routing"
        case .planning: return "Planning"
        case .research: return "Context research"
        case .execution: return "Execution"
        case .review: return "Review"
        case .correction: return "Correction"
        case .compaction: return "Summary / handoff"
        case .vision: return "Vision / OCR"
        case .finalResponse: return "Final response"
        }
    }

    /// Short explanation of what this role actually does in the turn graph.
    var roleDescription: String {
        switch self {
        case .dispatch: return "Classifies the request without doing the work."
        case .planning: return "Builds a plan and acceptance criteria."
        case .research: return "Collects evidence from available tools."
        case .execution: return "Produces edits, tool calls and the working answer."
        case .review: return "Independently checks changes, tests and risks."
        case .correction: return "Fixes concrete findings from review."
        case .compaction: return "Summarizes history for later model calls."
        case .vision: return "Extracts actual image content and OCR."
        case .finalResponse: return "Assembles the user-facing result without inventing work."
        }
    }
}

/// Whether all work uses the composer's model or roles have their own targets.
enum ModelRoutingMode: String, Codable, CaseIterable, Sendable {
    case single
    case perRole
}

/// A concrete provider/model target and its optional request parameters.
struct ModelAssignment: Codable, Equatable, Hashable, Sendable {
    var providerID: String
    var modelID: String
    var parameters: ModelCallParameters

    /// Trims identifiers on input; credentials never form part of this value.
    init(providerID: String, modelID: String, parameters: ModelCallParameters = ModelCallParameters()) {
        self.providerID = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.modelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.parameters = parameters
    }

    var isComplete: Bool { !providerID.isEmpty && !modelID.isEmpty }
}

/// Persisted routing settings. Inactive role assignments intentionally survive
/// switching back to single-model mode.
struct ModelRoutingConfiguration: Codable, Equatable, Sendable {
    var mode: ModelRoutingMode
    var assignments: [ModelRole: ModelAssignment]

    init(mode: ModelRoutingMode = .single, assignments: [ModelRole: ModelAssignment] = [:]) {
        self.mode = mode
        self.assignments = assignments
    }

    /// Number of complete role overrides shown in the compact picker label.
    var configuredRoleCount: Int {
        assignments.values.filter(\.isComplete).count
    }

    /// Changes mode without discarding the user's role configuration.
    func changingMode(to mode: ModelRoutingMode) -> ModelRoutingConfiguration {
        ModelRoutingConfiguration(mode: mode, assignments: assignments)
    }
}

/// Routing failures are explicit so no request silently goes to another model.
enum ModelRoutingError: Error, Equatable, LocalizedError {
    case missingAssignment(role: ModelRole)
    case unavailableProvider(providerID: String)
    case unavailableModel(role: ModelRole, modelID: String)
    case visionUnavailable
    case webRoleUnsupported(role: ModelRole, configID: String)
    case imagesUnsupported(role: ModelRole, modelID: String)

    var errorDescription: String? {
        switch self {
        case .missingAssignment(let role):
            return "Choose a provider and model for \(role.displayName). No fallback provider will be used."
        case .unavailableProvider(let providerID):
            return "Provider \(providerID) is not available. Reconnect it or choose another route."
        case .unavailableModel(let role, let modelID):
            return "Model \(modelID) assigned to \(role.displayName) is no longer available. Choose another model."
        case .visionUnavailable:
            return "The main model cannot process images. Assign an available Vision / OCR model before sending."
        case .webRoleUnsupported(let role, let configID):
            return "The web provider \"\(configID)\" cannot run the \(role.displayName) role: browser web chats only support the interactive single-model turn. Assign a direct provider/model to this role."
        case .imagesUnsupported(let role, let modelID):
            return "Model \(modelID) assigned to \(role.displayName) is reached through a text-only transport and cannot receive the attached images. Assign a vision-capable direct model to this role."
        }
    }
}

/// Pure resolver shared by the composer, transports, internal planners and UI.
struct ModelRouteResolver: Sendable {
    let configuration: ModelRoutingConfiguration
    let primary: ModelAssignment

    /// Returns the exact target for a role; single mode always uses `primary`.
    func assignment(for role: ModelRole) -> ModelAssignment? {
        configuration.mode == .single ? primary : (configuration.assignments[role] ?? primary)
    }

    /// All roles resolved for the visible chain preview; no network access.
    var resolvedAssignments: [ModelRole: ModelAssignment] {
        Dictionary(uniqueKeysWithValues: ModelRole.allCases.compactMap { role in
            assignment(for: role).map { (role, $0) }
        })
    }

    /// Whether the resolved chain will send data to more than one provider.
    var usesMultipleProviders: Bool {
        Set(resolvedAssignments.values.map(\.providerID)).count > 1
    }

    /// Resolves and validates one target against the current provider catalog.
    func validatedAssignment(
        for role: ModelRole,
        availableModels: [String: [String]]? = nil
    ) throws -> ModelAssignment {
        guard let target = assignment(for: role), target.isComplete else {
            // A missing vision model gets its own error: the composer must
            // offer a vision-capable choice instead of a generic message.
            if role == .vision { throw ModelRoutingError.visionUnavailable }
            throw ModelRoutingError.missingAssignment(role: role)
        }
        if let availableModels {
            try Self.validate(target, role: role, availableModels: availableModels)
        }
        return target
    }

    /// Validates only known catalog entries; absent metadata is not permission
    /// to substitute another provider or model.
    static func validate(
        _ assignment: ModelAssignment,
        role: ModelRole,
        availableModels: [String: [String]]
    ) throws {
        guard assignment.isComplete else { throw ModelRoutingError.missingAssignment(role: role) }
        guard let models = availableModels[assignment.providerID] else {
            throw ModelRoutingError.unavailableProvider(providerID: assignment.providerID)
        }
        guard models.contains(assignment.modelID) else {
            throw ModelRoutingError.unavailableModel(role: role, modelID: assignment.modelID)
        }
    }
}

/// Codable project defaults plus optional per-chat overrides in UserDefaults.
struct ModelRoutingStore {
    private let defaults: UserDefaults
    private let projectKey = "com.mycoder.modelRouting.projects"
    private let chatKey = "com.mycoder.modelRouting.chats"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// Resolves chat override first, then normalized project default.
    func configuration(projectRoot: String, sessionID: String?) -> ModelRoutingConfiguration? {
        if let sessionID, let chat: ModelRoutingConfiguration = read(key: chatKey, id: sessionID) {
            return chat
        }
        let root = ChatSession.normalizedPath(projectRoot)
        guard !root.isEmpty else { return nil }
        return read(key: projectKey, id: root)
    }

    /// Project default only (scope toggle in the routing menu reads it when
    /// the user switches editing from «Чат» to «Проект»).
    func projectConfiguration(projectRoot: String) -> ModelRoutingConfiguration? {
        let root = ChatSession.normalizedPath(projectRoot)
        guard !root.isEmpty else { return nil }
        return read(key: projectKey, id: root)
    }

    /// Chat override only (nil means the chat follows its project default).
    func chatConfiguration(sessionID: String) -> ModelRoutingConfiguration? {
        guard !sessionID.isEmpty else { return nil }
        return read(key: chatKey, id: sessionID)
    }

    /// Saves the default chain for a normalized project path.
    func saveProject(_ configuration: ModelRoutingConfiguration, projectRoot: String) {
        let root = ChatSession.normalizedPath(projectRoot)
        guard !root.isEmpty else { return }
        write(configuration, key: projectKey, id: root)
    }

    /// Saves a chat-specific override without changing its project default.
    func saveChat(_ configuration: ModelRoutingConfiguration, sessionID: String) {
        guard !sessionID.isEmpty else { return }
        write(configuration, key: chatKey, id: sessionID)
    }

    /// Removes only the chat override, revealing the project default again.
    func clearChat(sessionID: String) {
        var map = dictionary(for: chatKey)
        map.removeValue(forKey: sessionID)
        save(map, key: chatKey)
    }

    private func read<T: Decodable>(key: String, id: String) -> T? {
        guard let data = dictionary(for: key)[id] else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func write<T: Encodable>(_ value: T, key: String, id: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        var map = dictionary(for: key)
        map[id] = data
        save(map, key: key)
    }

    private func dictionary(for key: String) -> [String: Data] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: Data].self, from: data)) ?? [:]
    }

    private func save(_ map: [String: Data], key: String) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        defaults.set(data, forKey: key)
    }
}
