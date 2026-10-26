import Foundation

struct GitChanges {
    let additions: Int
    let deletions: Int
    
    var net: Int { additions - deletions }
    var formatted: String { "+\(additions) -\(deletions)" }
}

struct FileChange: Identifiable {
    let id = UUID()
    let path: String
    let additions: Int
    let deletions: Int
    let status: FileChangeStatus
    
    var displayStatus: String {
        switch status {
        case .edited: return "Edited"
        case .added: return "Added"
        case .deleted: return "Deleted"
        case .renamed: return "Renamed"
        }
    }
}

enum FileChangeStatus: String {
    case edited, added, deleted, renamed
}

struct TaskStep: Identifiable {
    let id = UUID()
    let title: String
    var status: StepStatus
}

enum StepStatus: String {
    case completed, inProgress, waiting
}

struct TaskProgress {
    let steps: [TaskStep]
    
    var completedCount: Int { steps.filter { $0.status == .completed }.count }
    var waitingCount: Int { steps.filter { $0.status == .waiting }.count }
    var inProgressCount: Int { steps.filter { $0.status == .inProgress }.count }
    var totalCount: Int { steps.count }
    var formatted: String { "\(completedCount)/\(totalCount)" }
}

enum ProviderStatus: String, Codable {
    case enabled, disabled
}
