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
}

enum ToolCallInspectorLogic {
    static func headerTitle(for steps: [ToolCallInspectorStep]) -> String {
        guard let first = steps.first else { return "Execution" }
        let title = ToolCallPresentationLogic.title(name: first.name, args: first.args)
        guard steps.count > 1 else { return title }
        return "\(title) · \(steps.count) steps"
    }

    static func isComplete(_ steps: [ToolCallInspectorStep]) -> Bool {
        !steps.isEmpty && steps.allSatisfy { $0.result != nil }
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

    static func title(name: String, args: String) -> String {
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
