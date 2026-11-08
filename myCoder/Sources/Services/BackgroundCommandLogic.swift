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
    let createdAt: Date
    var state: State = .running
    var output: String = ""
    var exitCode: Int?
    var finishedAt: Date?

    init(id: String = UUID().uuidString,
         command: String,
         workingDirectory: String,
         createdAt: Date = Date()) {
        self.id = id
        self.command = command
        self.workingDirectory = workingDirectory
        self.createdAt = createdAt
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
}
