import Foundation

enum UndoActionResult: Equatable {
    case undone
    case nothingToUndo
    case failed(String)
}

enum UndoActionFeedbackTone: Equatable {
    case success
    case warning
    case error
}

enum UndoActionFeedbackLogic {
    static func tone(for result: UndoActionResult) -> UndoActionFeedbackTone {
        switch result {
        case .undone: return .success
        case .nothingToUndo: return .warning
        case .failed: return .error
        }
    }

    static func message(for result: UndoActionResult) -> String {
        switch result {
        case .undone:
            return "Last file change undone."
        case .nothingToUndo:
            return "Nothing to undo."
        case .failed(let reason):
            return "Undo failed: \(reason)"
        }
    }
}
