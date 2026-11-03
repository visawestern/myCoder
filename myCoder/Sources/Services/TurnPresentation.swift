import Foundation

/// Pure formatting shared by the stored inspection snapshot and message UI.
enum TurnPresentation {
    static func rawText(events: [String]?, fallback: String) -> String {
        guard let events, !events.isEmpty else { return fallback }
        return events.joined(separator: "\n\n")
    }

    static func payload(system: String, context: String, request: String) -> String {
        "## Системная инструкция\n\(system)\n\n## Точечный контекст\n\(context)\n\n## Запрос пользователя\n\(request)"
    }

    /// Stable groups keep the tab bar usable when a turn includes many files.
    static func inspectionTabs(_ text: String) -> [ContextSection] {
        var groups: [String: [String]] = [:]
        for section in sections(text) {
            let group: String
            switch section.title {
            case "Системная инструкция": group = "Инструкции"
            case "План запроса", "Состояние задачи", "Вопросы внутренней модели", "Инструкции задачи": group = "Задача"
            case "История чата": group = "Диалог"
            case "Память проекта": group = "Память"
            case "Граф кода", "Вопросы харнесса о зависимостях": group = "Связи"
            case "Пробелы", "Не вошло": group = "Пробелы"
            case "Запрос", "Запрос пользователя": group = "Запрос"
            case "Контекст", "Точечный контекст": group = "Контекст"
            default:
                if section.title.hasPrefix("Инструкции проекта") { group = "Инструкции" }
                else if section.title.hasPrefix("Скилл:") { group = "Навыки" }
                else { group = "Файлы" }
            }
            groups[group, default: []].append("## \(section.title)\n\(section.body)")
        }
        return ["Инструкции", "Задача", "Диалог", "Память", "Навыки", "Связи", "Файлы", "Пробелы", "Контекст", "Запрос"]
            .compactMap { title in
                guard let bodies = groups[title] else { return nil }
                return ContextSection(title: title, body: bodies.joined(separator: "\n\n"))
            }
    }

    static func sections(_ text: String) -> [ContextSection] {
        var result: [ContextSection] = []
        var title = "Контекст"
        var lines: [String] = []
        func flush() {
            let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { result.append(ContextSection(title: title, body: body)) }
        }
        var fence: String?
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let marker = String(trimmed.prefix(while: { $0 == trimmed.first }))
                if fence == nil { fence = marker }
                else if marker == fence { fence = nil }
                lines.append(line)
                continue
            }
            if fence == nil, line.hasPrefix("## ") {
                flush()
                title = String(line.dropFirst(3))
                lines = []
            } else { lines.append(line) }
        }
        flush()
        return result
    }
}

/// Uses only models explicitly assigned to internal work, with validated pointers.
enum InternalContextPlanner {
    /// Send-time budget for the internal model's planning call.
    ///
    /// This used to inherit `LiveSpecCompletionProvider`'s 600 s window, which
    /// is right for a spec interview and wrong for a send: a wedged or slow
    /// local model left the turn "collecting context" for ten minutes with no
    /// way out (user report 2026-11-03). Assembly is an optimisation, not a
    /// prerequisite — past the budget we fall back to the deterministic plan.
    static let defaultBudget: TimeInterval = 20

    static func plan(message: String, context: LocalPlannerContext,
                     budget: TimeInterval = defaultBudget,
                     complete: @escaping @Sendable ([DirectChatMessage]) async throws -> String = { messages in
                         try await InternalModelRunner.complete(messages: messages)
                     }) async -> LocalQueryPlanResult {
        let prompt = LocalPlannerPromptBuilder.build(message: message, context: context)
        do {
            let raw = try await withTimeout(seconds: budget) {
                try await complete([
                    DirectChatMessage(role: "system", content: prompt.system),
                    DirectChatMessage(role: "user", content: prompt.user)
                ])
            }
            let parsed = try LocalQueryPlanParser.parse(raw)
            let resolved = LocalQueryPlanParser.resolve(parsed, context: context)
            guard !resolved.plan.isEmpty else {
                return .init(plan: nil, status: .fallback(reason: "empty internal plan"), dropped: resolved.dropped)
            }
            return .init(plan: resolved.plan, status: .local(model: "внутренняя модель"), dropped: resolved.dropped)
        } catch is InternalModelRunner.NoModelError {
            // Named explicitly: "no internal model assigned" is a setup fact
            // the user can fix, not a transport failure to guess about.
            return .init(plan: nil, status: .fallback(reason: "внутренняя модель не назначена"), dropped: [])
        } catch {
            return .init(plan: nil, status: .fallback(reason: error.localizedDescription), dropped: [])
        }
    }

    struct TimeoutError: LocalizedError {
        let seconds: TimeInterval
        var errorDescription: String? {
            "internal model did not answer within \(Int(seconds))s"
        }
    }

    /// Runs `work` but gives up after `seconds`. The child task is cancelled,
    /// so a hung HTTP call does not keep the turn alive in the background.
    static func withTimeout<T: Sendable>(seconds: TimeInterval,
                                         _ work: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
                throw TimeoutError(seconds: seconds)
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw TimeoutError(seconds: seconds)
            }
            return first
        }
    }
}
