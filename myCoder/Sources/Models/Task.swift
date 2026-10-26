import Foundation

enum TaskStatus: String, Codable {
    case pending
    case inProgress
    case done
    case failed
}

struct TaskItem: Identifiable, Codable {
    let id: String
    var title: String
    var description: String?
    var status: TaskStatus
    var assignee: String?
    var duration: String?
    var createdAt: Date?
    
    init(id: String = UUID().uuidString, title: String, description: String? = nil, status: TaskStatus = .pending, duration: String? = nil) {
        self.id = id
        self.title = title
        self.description = description
        self.status = status
        self.duration = duration
        self.createdAt = Date()
    }
}

struct Goal: Identifiable, Codable {
    let id: String
    var title: String
    var description: String?
    var status: TaskStatus
    var tasks: [TaskItem]
    var isComplete: Bool
    let createdAt: Date?
    
    init(id: String = UUID().uuidString, title: String, description: String? = nil, tasks: [TaskItem] = [], isComplete: Bool = false) {
        self.id = id
        self.title = title
        self.description = description
        self.status = isComplete ? .done : .pending
        self.tasks = tasks
        self.isComplete = isComplete
        self.createdAt = Date()
    }
    
    var completedTasks: Int {
        tasks.filter { $0.status == .done }.count
    }
    
    var progress: Double {
        guard !tasks.isEmpty else { return 0 }
        return Double(completedTasks) / Double(tasks.count)
    }
    
    var progressText: String {
        "\(completedTasks)/\(tasks.count)"
    }
    
    var statsText: String {
        "\(progressText) · 2m · 89K tokens"
    }
}
