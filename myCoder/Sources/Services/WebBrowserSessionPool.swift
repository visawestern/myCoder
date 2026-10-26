import Foundation

/// Stable identity for one hidden browser conversation. The same provider can
/// have independent browser pages for different projects and chats while
/// sharing the vendor cookie store.
struct WebBrowserInstanceKey: Codable, Equatable, Hashable, Sendable {
    let projectID: String
    let chatID: String
    let providerID: String
    let activeSessionID: String

    init(projectID: String, chatID: String, providerID: String, activeSessionID: String = "default") {
        self.projectID = projectID
        self.chatID = chatID
        self.providerID = providerID
        self.activeSessionID = activeSessionID
    }

    var storageKey: String {
        [projectID, chatID, providerID, activeSessionID]
            .map { $0.isEmpty ? "-" : $0 }
            .joined(separator: "::")
    }
}

/// Audit record for a browser-driven action. This is intentionally plain Codable
/// so it can be persisted and inspected without importing WebKit or SwiftUI.
struct WebBrowserActionRecord: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let timestamp: Date
    let action: String
    let projectID: String
    let chatID: String
    let providerID: String
    let providerName: String
    let modelID: String
    let effort: WebEffort?
    let remoteChatID: String?
    let detail: String?

    init(id: String = UUID().uuidString,
         timestamp: Date = Date(),
         action: String,
         projectID: String,
         chatID: String,
         providerID: String,
         providerName: String,
         modelID: String,
         effort: WebEffort?,
         remoteChatID: String? = nil,
         detail: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.action = action
        self.projectID = projectID
        self.chatID = chatID
        self.providerID = providerID
        self.providerName = providerName
        self.modelID = modelID
        self.effort = effort
        self.remoteChatID = remoteChatID
        self.detail = detail
    }
}

enum WebBrowserActionJournal {
    static let storageKey = "com.mycoder.webBrowserActionJournal"
    static let maxRecords = 500

    static func load(defaults: UserDefaults = .standard) -> [WebBrowserActionRecord] {
        guard let data = defaults.data(forKey: storageKey),
              let records = try? JSONDecoder().decode([WebBrowserActionRecord].self, from: data) else {
            return []
        }
        return records
    }

    static func append(_ record: WebBrowserActionRecord,
                       defaults: UserDefaults = .standard) -> [WebBrowserActionRecord] {
        var records = load(defaults: defaults)
        records.append(record)
        if records.count > maxRecords {
            records.removeFirst(records.count - maxRecords)
        }
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: storageKey)
        }
        return records
    }
}
