import Foundation

struct Project: Identifiable, Codable {
    let id: String
    var name: String
    var path: String
    var description: String?
    var agent: String?
    var tasks: [TaskItem]?
    var goal: Goal?
    let createdAt: Date
    var lastOpenedAt: Date
    
    init(id: String = UUID().uuidString, name: String, path: String, description: String? = nil, agent: String? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.description = description
        self.agent = agent
        self.tasks = nil
        self.goal = nil
        self.createdAt = Date()
        self.lastOpenedAt = Date()
    }
    
    var initials: String {
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return "\(words[0].prefix(1))\(words[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}
