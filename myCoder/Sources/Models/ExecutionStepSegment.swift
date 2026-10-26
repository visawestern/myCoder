import Foundation

struct ExecutionStepSegment: Identifiable {
    let id: String
    let stepNumber: Int
    let isComplete: Bool
    let isActive: Bool
    let parts: [MessagePartContent]

    var showsStepHeader: Bool { stepNumber > 0 }
}
