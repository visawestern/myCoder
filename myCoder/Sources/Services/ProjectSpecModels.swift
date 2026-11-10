import Foundation

struct ProjectSpecSettings: Equatable {
    let projectID: String
    var plannerProviderID: String?
    var plannerModelID: String?
    var coderProviderID: String?
    var coderModelID: String?
    var status: String
    var currentStep: String
    var briefGoal: String?
    var briefStack: String?
    var briefConstraints: String?
    var createdAt: Int64
    var updatedAt: Int64
    var completedAt: Int64?
}

struct ProjectSpecChecklistItem: Equatable {
    let id: String
    let projectID: String
    let itemKey: String
    let title: String
    var state: String
    var detail: String?
    let sortOrder: Int64
    var updatedAt: Int64
}

struct ProjectSpecTurn: Equatable {
    let id: String
    let projectID: String
    let role: String
    let content: String
    let suggestedAnswersJSON: String?
    let sequence: Int64
    let createdAt: Int64
}

struct ProjectSpecRevision: Equatable {
    let id: String
    let projectID: String
    let version: Int64
    let contentMarkdown: String
    let summary: String?
    let source: String
    let parentRevisionID: String?
    let createdAt: Int64
}

struct ProjectSpecRequirement: Equatable {
    let id: String
    let projectID: String
    let revisionID: String
    let externalKey: String
    let title: String
    let description: String
    let priority: String
    var status: String
    let acceptanceCriteriaJSON: String?
    let createdAt: Int64
    var updatedAt: Int64
}

struct ProjectSpecNode: Equatable {
    let id: String
    let projectID: String
    let revisionID: String
    let externalKey: String
    let title: String
    let description: String
    let kind: String
    var status: String
    let sortOrder: Int64
    let acceptanceCriteriaJSON: String?
    let createdAt: Int64
    var updatedAt: Int64
}

struct ProjectSpecEdge: Equatable {
    let id: String
    let projectID: String
    let fromNodeID: String
    let toNodeID: String
    let kind: String
    let createdAt: Int64
}

struct ProjectSpecHistoryEntry: Equatable {
    let id: String
    let projectID: String
    let entityType: String
    let entityID: String
    let action: String
    let payloadJSON: String?
    let actor: String
    let createdAt: Int64
}

struct ProjectSpecNodeSession: Equatable {
    let id: String
    let projectID: String
    let nodeID: String
    let sessionID: String
    var state: String
    let createdAt: Int64
    var updatedAt: Int64
}

enum ProjectSpecStoreError: Error, Equatable, LocalizedError {
    case unknownNode(String)

    var errorDescription: String? {
        switch self {
        case .unknownNode(let id):
            return "Decomposition edge references unknown node \(id)"
        }
    }
}
