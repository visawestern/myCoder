import Foundation

struct ToolCallArgumentSection: Identifiable, Equatable {
    let key: String
    let value: String

    var id: String { key }
}

struct ToolCallInspectorStep: Identifiable {
    let id: String
    let name: String
    let args: String
    let result: String?
    /// Идентификатор вызова (callID) — ключ, по которому результат хранится
    /// в `ToolResultStore` и БД. `nil` допустим для шагов без callID
    /// (тогда ключом хранилища служит `id`).
    let callID: String?
    /// True, когда результат вызова существует в хранилище (БД или
    /// `ToolResultStore`), но ещё не загружен в `result`. Позволяет
    /// отличать «ещё не загружен» от «результата нет вовсе» — например,
    /// при ленивой загрузке истории без текстов результатов тулов.
    let hasStoredResult: Bool

    init(
        id: String,
        name: String,
        args: String,
        result: String?,
        callID: String? = nil,
        hasStoredResult: Bool = false
    ) {
        self.id = id
        self.name = name
        self.args = args
        self.result = result
        self.callID = callID
        self.hasStoredResult = hasStoredResult
    }
}

enum ToolCallInspectorLogic {
    static func headerTitle(for steps: [ToolCallInspectorStep]) -> String {
        guard let first = steps.first else { return "Execution" }
        let title = ToolCallPresentationLogic.title(name: first.name, args: first.args)
        guard steps.count > 1 else { return title }
        return "\(title) · \(steps.count) steps"
    }

    /// Завершён ли набор шагов: у каждого шага либо уже загружен текст
    /// результата (`result != nil`), либо результат существует в хранилище
    /// (`hasStoredResult`) — незагруженный, но существующий результат не
    /// делает шаг «активным».
    static func isComplete(_ steps: [ToolCallInspectorStep]) -> Bool {
        !steps.isEmpty && steps.allSatisfy { $0.result != nil || $0.hasStoredResult }
    }

    static func copyText(for steps: [ToolCallInspectorStep]) -> String {
        steps.enumerated().map { index, step in
            var chunks = [
                "\(index + 1). \(step.name)",
                "Arguments:",
                step.args,
            ]
            if let result = step.result, !result.isEmpty {
                chunks.append(contentsOf: ["Result:", result])
            }
            return chunks.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}

enum ToolCallPresentationLogic {
    /// Max width of the "what it reads/writes" summary in a plan-tool header.
    /// Longer content is cut with an ellipsis so the header always fits one
    /// line (user directive 2026-11-10, T1).
    static let planSummaryMaxWidth = 80

    /// Plan/checklist tools always keep their real tool name plus a one-line
    /// summary of what the call reads or writes. The generic
    /// contains("read")/contains("write") heuristics in `title` used to render
    /// `todo_read` as "Reading file" and `todo_write`/`task_create` as
    /// "Writing code" (T1 bug).
    ///
    /// Вход: имя инструмента в любом алиасе (todoread, read_todos, …) и
    /// JSON-строка аргументов.
    /// Выход: заголовок вида «todo_read · reads checklist + plan» или nil для
    /// непла новых инструментов.
    /// Зависимости: `WebToolProtocolEmulator.canonicalToolName`, `WebEmulatedTool`.
    static func planToolTitle(name: String, args: String) -> String? {
        guard let canonical = WebToolProtocolEmulator.canonicalToolName(name),
              let tool = WebEmulatedTool(rawValue: canonical) else { return nil }
        switch tool {
        case .todoRead:
            return "todo_read · reads checklist + plan"
        case .taskList:
            return "task_list · reads the step list"
        case .todoWrite:
            let items = planItems(from: args)
            guard let first = items.first.flatMap(planItemText) else {
                return "todo_write · writes the checklist"
            }
            return "todo_write · writes checklist (\(items.count)): \(oneLineTruncated(first))"
        case .taskCreate:
            guard let content = planArgument(args, keys: ["content", "title", "description", "task", "text"]) else {
                return "task_create · adds a plan step"
            }
            return "task_create · adds step: \(oneLineTruncated(content))"
        case .taskUpdate:
            let id = planArgument(args, keys: ["id"])
            let status = planArgument(args, keys: ["status"])
            let content = planArgument(args, keys: ["content", "title", "description"])
            if let id {
                if let status {
                    return "task_update · step \(oneLineTruncated(id)) → \(oneLineTruncated(status))"
                }
                if let content {
                    return "task_update · step \(oneLineTruncated(id)): \(oneLineTruncated(content))"
                }
                return "task_update · step \(oneLineTruncated(id))"
            }
            if let status {
                return "task_update · sets status \(oneLineTruncated(status))"
            }
            return "task_update · updates a plan step"
        default:
            // Not a plan tool (task/todo aliases are exhaustive above).
            return nil
        }
    }

    static func argumentSections(from arguments: String) -> [ToolCallArgumentSection] {
        guard let data = arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return [ToolCallArgumentSection(key: "value", value: arguments)]
        }

        let keys = dictionary.keys.sorted { lhs, rhs in
            argumentPriority(lhs) < argumentPriority(rhs)
                || (argumentPriority(lhs) == argumentPriority(rhs) && lhs < rhs)
        }
        return keys.map { key in
            ToolCallArgumentSection(key: key, value: displayValue(dictionary[key] as Any))
        }
    }

    /// Checklist items from a todo_write payload: accepts a bare array and
    /// the {"todos": [...]} wrapper (same contract as `ProjectWebToolExecutor`).
    ///
    /// Вход: JSON-строка аргументов. Выход: массив словарей-элементов.
    /// Зависимости: `JSONSerialization`.
    private static func planItems(from args: String) -> [[String: Any]] {
        guard let data = args.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        if let array = json as? [[String: Any]] { return array }
        if let dict = json as? [String: Any] {
            for key in ["todos", "items", "tasks"] {
                if let array = dict[key] as? [[String: Any]] { return array }
            }
        }
        return []
    }

    /// Display text of one checklist item (first non-empty canonical key).
    private static func planItemText(_ item: [String: Any]) -> String? {
        planValue(item, keys: ["content", "title", "text", "description"])
    }

    /// First non-empty string value among `keys` in a flat args object.
    /// Keys are matched case-insensitively; numbers are stringified so a
    /// numeric step id still shows in the header.
    private static func planArgument(_ args: String, keys: [String]) -> String? {
        guard let data = args.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let dict = json as? [String: Any] else {
            return nil
        }
        return planValue(dict, keys: keys)
    }

    private static func planValue(_ dict: [String: Any], keys: [String]) -> String? {
        let lowered = Dictionary(uniqueKeysWithValues: dict.map { ($0.key.lowercased(), $0.value) })
        for key in keys {
            if let string = lowered[key] as? String,
               !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return string
            }
            if let number = lowered[key] as? NSNumber {
                return number.stringValue
            }
        }
        return nil
    }

    /// Collapses newlines/extra spaces into single spaces and truncates with
    /// an ellipsis so a header never exceeds one line.
    private static func oneLineTruncated(_ value: String) -> String {
        let cleaned = value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard cleaned.count > planSummaryMaxWidth else { return cleaned }
        return cleaned.prefix(planSummaryMaxWidth) + "…"
    }

    static func title(name: String, args: String) -> String {
        // T1: plan/checklist tools keep their real name — the generic
        // heuristics below would rename todo_read to "Reading file".
        if let planTitle = planToolTitle(name: name, args: args) {
            return planTitle
        }
        let values = Dictionary(
            uniqueKeysWithValues: argumentSections(from: args).map { ($0.key.lowercased(), $0.value) }
        )
        let normalizedName = name.lowercased()
        let path = firstValue(
            keys: ["path", "filepath", "file", "filename"],
            values: values
        )
        let filename = path.map { ($0 as NSString).lastPathComponent }

        if normalizedName.contains("write") || normalizedName.contains("create") {
            return filename.map { "Writing \($0)" } ?? "Writing code"
        }
        if normalizedName.contains("edit") || normalizedName.contains("patch") {
            return filename.map { "Editing \($0)" } ?? "Editing code"
        }
        if normalizedName.contains("read") {
            return filename.map { "Reading \($0)" } ?? "Reading file"
        }
        if normalizedName.contains("search") || normalizedName == "grep" || normalizedName == "rg" {
            let query = firstValue(keys: ["query", "pattern", "search"], values: values)
            return query.map { "Searching for \(singleLine($0))" } ?? "Searching project"
        }
        if normalizedName.contains("shell") || normalizedName == "bash" || normalizedName == "run" {
            let command = firstValue(keys: ["command", "cmd"], values: values)
            return command.map { "Running \(singleLine($0))" } ?? "Running command"
        }
        if normalizedName.contains("fetch") {
            let target = firstValue(keys: ["url", "path"], values: values)
            return target.map { "Fetching \(singleLine($0))" } ?? "Fetching data"
        }
        if normalizedName.contains("task") {
            let description = firstValue(
                keys: ["description", "title", "prompt", "task", "message"],
                values: values
            )
            return description.map(singleLine) ?? "Running task"
        }
        if normalizedName.contains("sleep") || normalizedName == "wait" {
            let duration = firstValue(keys: ["duration", "seconds", "time", "ms", "delay"], values: values)
            return duration.map { "⏳ Waiting \(singleLine($0))s" } ?? "Waiting"
        }

        if let description = firstValue(
            keys: ["description", "title", "prompt", "message"],
            values: values
        ) {
            return singleLine(description)
        }

        return name.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static func formattedResult(_ result: String) -> String {
        guard let data = result.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let formatted = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys]
              ),
              let string = String(data: formatted, encoding: .utf8) else {
            return result
        }
        return string
    }

    private static func displayValue(_ value: Any) -> String {
        if let string = value as? String {
            guard let nestedData = string.data(using: .utf8),
                  let nested = try? JSONSerialization.jsonObject(with: nestedData),
                  JSONSerialization.isValidJSONObject(nested),
                  let formatted = try? JSONSerialization.data(
                    withJSONObject: nested,
                    options: [.prettyPrinted, .sortedKeys]
                  ) else {
                return string
            }
            return String(data: formatted, encoding: .utf8) ?? string
        }

        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(
               withJSONObject: value,
               options: [.prettyPrinted, .sortedKeys]
           ) {
            return String(data: data, encoding: .utf8) ?? String(describing: value)
        }
        if value is NSNull {
            return "null"
        }
        return String(describing: value)
    }

    private static func firstValue(
        keys: [String],
        values: [String: String]
    ) -> String? {
        keys.compactMap { values[$0] }.first { !$0.isEmpty }
    }

    private static func singleLine(_ value: String) -> String {
        value.split(whereSeparator: \.isNewline).first.map(String.init) ?? value
    }

    private static func argumentPriority(_ key: String) -> Int {
        switch key.lowercased() {
        case "path", "filepath", "file", "filename":
            return 0
        case "content", "code", "command":
            return 1
        default:
            return 2
        }
    }
}
