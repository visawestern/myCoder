import Foundation

/// Состояние одной фоновой команды (терминал).
struct BackgroundCommandTask: Identifiable, Equatable, Sendable {
    enum State: String, Sendable {
        case running
        case completed
        case terminated
    }

    let id: String
    let command: String
    let workingDirectory: String
    /// Chat that started the command. The right-panel terminal shows only the
    /// commands of the open chat (user directive 2026-11-13); nil is kept for
    /// legacy callers that do not belong to a chat.
    let sessionID: String?
    let createdAt: Date
    var state: State = .running
    var output: String = ""
    var exitCode: Int?
    var finishedAt: Date?

    init(id: String = UUID().uuidString,
         command: String,
         workingDirectory: String,
         createdAt: Date = Date(),
         sessionID: String? = nil) {
        self.id = id
        self.command = command
        self.workingDirectory = workingDirectory
        self.createdAt = createdAt
        self.sessionID = sessionID
    }

    var isCompleted: Bool { exitCode != nil }

    /// Короткий заголовок для сайдбара (первая строка команды).
    var displayTitle: String {
        let firstLine = command
            .split(separator: "\n", omittingEmptySubsequences: false)
            .first.map(String.init) ?? command
        return firstLine.count > 44 ? String(firstLine.prefix(44)) + "…" : firstLine
    }
}

/// Чистая логика фонового терминала: форматирование и сортировка.
enum BackgroundCommandLogic {

    /// The right panel keeps only the newest commands — the list must not grow
    /// without bound over a long session (user directive 2026-11-13).
    static let maxVisibleTasks = 10

    static func renderResult(output: String, exitCode: Int) -> String {
        var text = output.isEmpty ? "(нет вывода)" : output
        text += "\n(exit \(exitCode))"
        return text
    }

    /// Активные задачи — новые сверху.
    static func sortedActive(_ tasks: [BackgroundCommandTask]) -> [BackgroundCommandTask] {
        tasks.sorted { $0.createdAt > $1.createdAt }
    }

    /// Завершённые задачи — новые сверху.
    static func sortedFinished(_ tasks: [BackgroundCommandTask]) -> [BackgroundCommandTask] {
        tasks.sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
    }

    /// Commands visible in one chat's terminal: strictly that chat's tasks,
    /// active first, newest first, capped at `limit`. Without an open chat the
    /// list is empty — a command never floats into another chat's panel.
    static func visibleTasks(_ tasks: [BackgroundCommandTask],
                             sessionID: String?,
                             limit: Int = maxVisibleTasks) -> [BackgroundCommandTask] {
        guard let sessionID, !sessionID.isEmpty else { return [] }
        let mine = tasks.filter { $0.sessionID == sessionID }
        let active = sortedActive(mine.filter { !$0.isCompleted })
        let finished = sortedFinished(mine.filter(\.isCompleted))
        return Array((active + finished).prefix(max(0, limit)))
    }
}
