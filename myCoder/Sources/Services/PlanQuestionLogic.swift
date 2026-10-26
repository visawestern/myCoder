import Foundation

struct PlanQuestionOption: Identifiable, Equatable {
    let id: String
    let label: String
    let description: String
}

struct PlanQuestion: Identifiable, Equatable {
    let id: String
    let header: String
    let prompt: String
    let options: [PlanQuestionOption]
    let allowsMultiple: Bool
}

struct PendingQuestionRequest: Equatable {
    let requestID: String
    let sessionID: String
    let questions: [PlanQuestion]
}

struct OpenCodeToolPartParseResult: Equatable {
    let toolName: String
    let argsJSON: String
    let isPending: Bool
    let result: String?
    let questions: [PlanQuestion]
    let callID: String?
}

enum PlanQuestionLogic {
    static func isQuestionTool(_ name: String) -> Bool {
        let normalized = name.lowercased()
            .replacingOccurrences(of: "-", with: "_")
        if normalized == "question" { return true }
        if normalized == "askuserquestion" || normalized == "ask_user" { return true }
        if normalized.hasSuffix("ask_user") || normalized.hasSuffix("askuserquestion") { return true }
        return normalized.contains("askuserquestion") || normalized.contains("ask_user")
    }

    static func parseQuestionAskedEvent(properties: [String: Any]) -> PendingQuestionRequest? {
        guard let requestID = properties["requestID"] as? String,
              !requestID.isEmpty else {
            return nil
        }
        let sessionID = properties["sessionID"] as? String ?? ""
        let rawQuestions = properties["questions"] as? [[String: Any]] ?? []
        let questions = parseQuestionsArray(rawQuestions)
        guard !questions.isEmpty else { return nil }
        return PendingQuestionRequest(requestID: requestID, sessionID: sessionID, questions: questions)
    }

    static func parseOpenCodeToolPart(_ part: [String: Any]) -> OpenCodeToolPartParseResult? {
        guard let partType = part["type"] as? String else { return nil }

        if partType == "tool" {
            let toolName = part["tool"] as? String ?? "tool"
            let callID = part["callID"] as? String ?? part["id"] as? String
            let state = part["state"] as? [String: Any]
            let status = state?["status"] as? String
            let input = state?["input"] as? [String: Any] ?? part["input"] as? [String: Any] ?? [:]
            let argsJSON = jsonString(from: input) ?? "{}"
            let questions = parseQuestions(from: argsJSON)
            let output = OpenCodeToolStatusLogic.extractOutput(from: state)
            let isPending = OpenCodeToolStatusLogic.isPending(status: status, output: output)
            let result = isPending ? nil : output
            return OpenCodeToolPartParseResult(
                toolName: toolName,
                argsJSON: argsJSON,
                isPending: isPending,
                result: result,
                questions: questions,
                callID: callID
            )
        }

        if partType == "tool-invocation" || partType == "tool-call" {
            let toolName = part["toolName"] as? String ?? part["name"] as? String ?? "tool"
            let callID = part["callID"] as? String ?? part["id"] as? String
            let input = stringInput(from: part["input"])
                ?? stringInput(from: part["args"])
                ?? stringInput(from: part["arguments"])
                ?? "{}"
            let result = part["result"] as? String
            let questions = parseQuestions(from: input)
            return OpenCodeToolPartParseResult(
                toolName: toolName,
                argsJSON: input,
                isPending: result == nil,
                result: result,
                questions: questions,
                callID: callID
            )
        }

        return nil
    }

    static func parseQuestions(from argsJSON: String) -> [PlanQuestion] {
        guard let data = argsJSON.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }

        if let dict = root as? [String: Any],
           let rawQuestions = dict["questions"] as? [[String: Any]] {
            return parseQuestionsArray(rawQuestions)
        }

        if let rawQuestions = root as? [[String: Any]] {
            return parseQuestionsArray(rawQuestions)
        }

        return []
    }

    static func parseQuestionsArray(_ rawQuestions: [[String: Any]]) -> [PlanQuestion] {
        rawQuestions.enumerated().compactMap { index, item in
            let prompt = (item["question"] as? String) ?? (item["prompt"] as? String) ?? ""
            guard !prompt.isEmpty else { return nil }

            let header = (item["header"] as? String) ?? "Question \(index + 1)"
            let allowsMultiple = (item["multiple"] as? Bool)
                ?? (item["multiSelect"] as? Bool)
                ?? false
            let options = parseOptions(item["options"])

            return PlanQuestion(
                id: "q-\(index)",
                header: header,
                prompt: prompt,
                options: options,
                allowsMultiple: allowsMultiple
            )
        }
    }

    static func buildReplyAnswers(
        questions: [PlanQuestion],
        selections: [String: Set<String>],
        otherTexts: [String: String]
    ) -> [[String]] {
        questions.map { question in
            var labels = question.options
                .filter { (selections[question.id] ?? []).contains($0.id) }
                .map(\.label)
            if let other = otherTexts[question.id]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !other.isEmpty {
                labels.append(other)
            }
            return labels
        }
    }

    static func formatAnswers(_ questions: [PlanQuestion], selections: [String: Set<String>]) -> String {
        var lines: [String] = ["Answers:"]
        for question in questions {
            let selected = selections[question.id] ?? []
            let labels = question.options.filter { selected.contains($0.id) }.map(\.label)
            if labels.isEmpty {
                lines.append("- \(question.prompt): Other")
            } else {
                lines.append("- \(question.prompt): \(labels.joined(separator: ", "))")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func hasPendingQuestions(in parts: [MessagePartContent]) -> Bool {
        parts.contains { part in
            if case .toolCall(let name, let args, let result, _) = part {
                guard isQuestionTool(name) else { return false }
                if result != nil { return false }
                return !parseQuestions(from: args).isEmpty || name.lowercased() == "question"
            }
            return false
        }
    }

    static func upsertToolCall(
        _ parts: inout [MessagePartContent],
        name: String,
        args: String,
        result: String?,
        callID: String? = nil
    ) {
        if let callID, !callID.isEmpty,
           let index = parts.lastIndex(where: { part in
               if case .toolCall(_, _, _, let existingID) = part {
                   return existingID == callID
               }
               return false
           }) {
            parts[index] = .toolCall(name: name, args: args, result: result, callID: callID)
            return
        }

        if let index = parts.lastIndex(where: { part in
            if case .toolCall(let existingName, _, _, _) = part {
                return existingName == name
            }
            return false
        }) {
            parts[index] = .toolCall(name: name, args: args, result: result, callID: callID)
        } else {
            parts.append(.toolCall(name: name, args: args, result: result, callID: callID))
        }
    }

    private static func parseOptions(_ raw: Any?) -> [PlanQuestionOption] {
        guard let options = raw as? [[String: Any]] else { return [] }
        return options.enumerated().compactMap { index, option in
            let label = (option["label"] as? String) ?? (option["title"] as? String) ?? ""
            guard !label.isEmpty else { return nil }
            let description = (option["description"] as? String) ?? ""
            return PlanQuestionOption(id: "opt-\(index)", label: label, description: description)
        }
    }

    private static func stringInput(from value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let dict as [String: Any]:
            return jsonString(from: dict)
        case let array as [[String: Any]]:
            return jsonString(from: ["questions": array])
        default:
            return nil
        }
    }

    private static func jsonString(from value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }
}
