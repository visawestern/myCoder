import Foundation

/// Persistent storage for goals (ЦЕЛЬ) at `~/.mycoder/goals.json`.
/// Mirrors the MCP/LSP registries: a small document with a list, upsert-aware,
/// date-encoded ISO8601.
struct GoalStoreDocument: Codable, Equatable {
    var goals: [UserGoal]
}

enum GoalStore {

    static func storeURL(homeDirectory: URL) -> URL {
        MyCoderPaths.goalsURL(homeDirectory: homeDirectory)
    }

    static func load(homeDirectory: URL, fileManager: FileManager = .default) -> [UserGoal] {
        let url = storeURL(homeDirectory: homeDirectory)
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let doc = try? decoder.decode(GoalStoreDocument.self, from: data) else { return [] }
        return doc.goals.sorted { $0.updatedAt > $1.updatedAt }
    }

    static func save(_ goals: [UserGoal], homeDirectory: URL, fileManager: FileManager = .default) throws {
        let url = storeURL(homeDirectory: homeDirectory)
        let dir = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(GoalStoreDocument(goals: goals))
        try data.write(to: url, options: .atomic)
    }

    @discardableResult
    static func upsert(_ goal: UserGoal, homeDirectory: URL, fileManager: FileManager = .default) throws -> Bool {
        var goals = load(homeDirectory: homeDirectory, fileManager: fileManager)
        if let idx = goals.firstIndex(where: { $0.id == goal.id }) {
            goals[idx] = goal
        } else {
            goals.append(goal)
        }
        try save(goals, homeDirectory: homeDirectory, fileManager: fileManager)
        return true
    }

    @discardableResult
    static func remove(id: UUID, homeDirectory: URL, fileManager: FileManager = .default) throws -> Bool {
        var goals = load(homeDirectory: homeDirectory, fileManager: fileManager)
        guard let idx = goals.firstIndex(where: { $0.id == id }) else { return false }
        goals.remove(at: idx)
        try save(goals, homeDirectory: homeDirectory, fileManager: fileManager)
        return true
    }

    /// Update a goal's state and touch `updatedAt`.
    @discardableResult
    static func setState(id: UUID, state: UserGoal.State, homeDirectory: URL, fileManager: FileManager = .default) throws -> Bool {
        var goals = load(homeDirectory: homeDirectory, fileManager: fileManager)
        guard let idx = goals.firstIndex(where: { $0.id == id }) else { return false }
        goals[idx].state = state
        goals[idx].updatedAt = Date()
        try save(goals, homeDirectory: homeDirectory, fileManager: fileManager)
        return true
    }

    /// Change a goal's title. An empty title or an unknown goal changes
    /// nothing — the caller gets `false` instead of a silent success.
    @discardableResult
    static func updateTitle(id: UUID, title: String, homeDirectory: URL, fileManager: FileManager = .default) throws -> Bool {
        guard let normalized = GoalEditingLogic.normalizedTitle(title) else { return false }
        var goals = load(homeDirectory: homeDirectory, fileManager: fileManager)
        guard let idx = goals.firstIndex(where: { $0.id == id }) else { return false }
        goals[idx].title = normalized
        goals[idx].updatedAt = Date()
        try save(goals, homeDirectory: homeDirectory, fileManager: fileManager)
        return true
    }
}
