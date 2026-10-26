import Foundation

enum ExecutionStepSyncLogic {
    static func steps(from parts: [MessagePartContent], existing: [TaskStep] = []) -> [TaskStep] {
        var steps: [TaskStep] = []
        var stepIndex = 0

        for part in parts {
            switch part {
            case .stepStart:
                stepIndex += 1
                let title = titleForStep(number: stepIndex, existing: existing)
                steps.append(TaskStep(title: title, status: .inProgress))
            case .stepFinish:
                if var last = steps.popLast() {
                    last.status = .completed
                    steps.append(last)
                }
            default:
                break
            }
        }

        return steps
    }

    static func mergedSteps(existing: [TaskStep], incoming: [TaskStep]) -> [TaskStep] {
        guard !incoming.isEmpty else { return existing }
        return incoming
    }

    private static func titleForStep(number: Int, existing: [TaskStep]) -> String {
        let index = number - 1
        guard existing.indices.contains(index) else { return "Step \(number)" }
        return existing[index].title
    }
}
