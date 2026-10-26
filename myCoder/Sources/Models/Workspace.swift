import Foundation

struct Workspace: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var path: String
    var branch: String?
    var tasks: [WorkspaceTask]
    
    init(id: String = UUID().uuidString, name: String, path: String, branch: String? = nil, tasks: [WorkspaceTask] = []) {
        self.id = id
        self.name = name
        self.path = path
        self.branch = branch
        self.tasks = tasks
    }
}

struct WorkspaceTask: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    var status: TaskStatus
    var duration: String?
    
    init(id: String = UUID().uuidString, title: String, status: TaskStatus = .pending, duration: String? = nil) {
        self.id = id
        self.title = title
        self.status = status
        self.duration = duration
    }
}
