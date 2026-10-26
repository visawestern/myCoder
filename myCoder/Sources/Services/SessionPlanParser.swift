import Foundation

enum SessionPlanParser {

    static func steps(from messages: [MimoMessageResponse]) -> [TaskStep] {
        if let todoSteps = stepsFromTodoWrite(in: messages), !todoSteps.isEmpty {
            return todoSteps
        }

        for message in messages.reversed() {
            let text = message.textContent
            if !text.isEmpty {
                let markdownSteps = steps(fromMarkdown: text)
                if !markdownSteps.isEmpty {
                    return markdownSteps
                }
            }
        }

        return stepsFromExecutionMarkers(in: messages)
    }

    static func steps(fromTodoWriteJSON input: String) -> [TaskStep]? {
        parseTodoWriteInput(input)
    }

    static func steps(fromMarkdown text: String) -> [TaskStep] {
        var steps: [TaskStep] = []
        var usedCheckboxes = false
        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let checkbox = parseCheckboxLine(trimmed) {
                usedCheckboxes = true
                steps.append(checkbox)
                continue
            }

            if parseStageLine(trimmed) != nil {
                let status: StepStatus = steps.isEmpty ? .inProgress : .waiting
                steps.append(TaskStep(title: trimmed, status: status))
                continue
            }

            if let numbered = parseNumberedLine(trimmed) {
                let status: StepStatus = steps.isEmpty ? .inProgress : .waiting
                steps.append(TaskStep(title: numbered, status: status))
            }
        }

        if !usedCheckboxes,
           steps.contains(where: { $0.status == .waiting }),
           !steps.contains(where: { $0.status == .inProgress }),
           let firstWaiting = steps.firstIndex(where: { $0.status == .waiting }) {
            steps[firstWaiting].status = .inProgress
        }

        return steps
    }

    private static func parseCheckboxLine(_ line: String) -> TaskStep? {
        guard let regex = try? NSRegularExpression(pattern: #"^-\s*\[(x|X|\s)\]\s+(.+)$"#),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges == 3,
              let markRange = Range(match.range(at: 1), in: line),
              let titleRange = Range(match.range(at: 2), in: line) else { return nil }

        let mark = String(line[markRange]).lowercased()
        let title = String(line[titleRange]).trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        return TaskStep(title: title, status: mark == "x" ? .completed : .waiting)
    }

    private static func parseStageLine(_ line: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"^(?:Этап|Step)\s+\d+[:.]?\s*.+$"#, options: [.caseInsensitive]),
              regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil else { return nil }
        return line
    }

    private static func parseNumberedLine(_ line: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"^\d+\.\s+(.+)$"#),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges == 2,
              let titleRange = Range(match.range(at: 1), in: line) else { return nil }
        let title = String(line[titleRange]).trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : title
    }

    private static func stepsFromTodoWrite(in messages: [MimoMessageResponse]) -> [TaskStep]? {
        var latest: [TaskStep]?

        for message in messages {
            guard let parts = message.parts else { continue }
            for part in parts {
                guard case .toolInvocation(let name, let input, _, _) = part,
                      name.lowercased() == "todowrite",
                      let input,
                      let parsed = parseTodoWriteInput(input) else { continue }
                latest = parsed
            }
        }

        return latest
    }

    private static func parseTodoWriteInput(_ input: String) -> [TaskStep]? {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let todos = json["todos"] as? [[String: Any]] else { return nil }

        let steps = todos.compactMap { todo -> TaskStep? in
            guard let content = todo["content"] as? String, !content.isEmpty else { return nil }
            let rawStatus = (todo["status"] as? String ?? "pending").lowercased()
            let status: StepStatus
            switch rawStatus {
            case "completed", "done":
                status = .completed
            case "cancelled":
                status = .waiting
            case "in_progress", "inprogress", "active":
                status = .inProgress
            default:
                status = .waiting
            }
            return TaskStep(title: content, status: status)
        }

        return steps.isEmpty ? nil : steps
    }

    private static func stepsFromExecutionMarkers(in messages: [MimoMessageResponse]) -> [TaskStep] {
        var steps: [TaskStep] = []
        var stepIndex = 0

        for message in messages {
            guard let parts = message.parts else { continue }
            for part in parts {
                switch part {
                case .stepStart:
                    stepIndex += 1
                    steps.append(TaskStep(title: "Step \(stepIndex)", status: .inProgress))
                case .stepFinish:
                    if var last = steps.popLast() {
                        last.status = .completed
                        steps.append(last)
                    }
                default:
                    break
                }
            }
        }

        return steps
    }
}
