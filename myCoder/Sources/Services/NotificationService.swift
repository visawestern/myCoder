import Foundation

extension Notification.Name {
    static let apiSendRequested = Notification.Name("apiSendRequested")
    /// Control of the model-switch compaction from outside the app: the
    /// banner's stop / roll back / compact again must be reachable over HTTP
    /// too (the accessibility tree is not always available).
    static let apiCompactionControlRequested = Notification.Name("apiCompactionControlRequested")
    static let webToolApprovalResolved = Notification.Name("webToolApprovalResolved")
    static let localToolApprovalResolved = Notification.Name("localToolApprovalResolved")
    /// Fired after any provider store (custom/local/web) changes so the
    /// unified provider list refreshes even when the store is not an
    /// ObservableObject.
    static let providersChanged = Notification.Name("com.mycoder.providersChanged")
}

// MARK: - Notification Model

struct AppNotification: Identifiable, Equatable {
    let id: String
    let title: String
    let message: String
    let type: NotificationType
    let timestamp: Date
    var isRead: Bool
    /// When the notification was read. Used to gray it out and to age it out
    /// of the list one hour after reading (user directive 2026-10-29).
    var readAt: Date?
    var action: NotificationAction?
    
    init(
        id: String = UUID().uuidString,
        title: String,
        message: String,
        type: NotificationType = .info,
        timestamp: Date = Date(),
        isRead: Bool = false,
        readAt: Date? = nil,
        action: NotificationAction? = nil
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.type = type
        self.timestamp = timestamp
        self.isRead = isRead
        self.readAt = readAt
        self.action = action
    }
}

enum NotificationType: String, Equatable {
    case info
    case success
    case warning
    case error
    
    var icon: String {
        switch self {
        case .info: return "info.circle"
        case .success: return "checkmark.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        }
    }
    
    var color: String {
        switch self {
        case .info: return "brand"
        case .success: return "success"
        case .warning: return "warning"
        case .error: return "error"
        }
    }
}

enum NotificationAction: Equatable {
    case openSession(String)  // session ID
    /// Opens a chat and scrolls to one concrete message, so tapping a
    /// tool-approval alert lands on the card that raised it instead of only
    /// opening the chat at the newest message.
    case openMessage(sessionID: String, messageID: String)
    case openSettings
    case openGit
    case custom(String)       // URL or action identifier
}


// MARK: - Notification Service

final class NotificationService: ObservableObject {
    @Published var notifications: [AppNotification] = []
    @Published private(set) var unreadCount: Int = 0
    
    private let maxNotifications = 50
    private var pruneTimer: Timer?
    /// Read notifications live for one hour, then drop out of the list.
    static let readLifetime: TimeInterval = 3600
    
    init() {
        startPruneTimer()
    }
    
    var sortedNotifications: [AppNotification] {
        pruneExpiredRead()
        return notifications.sorted { $0.timestamp > $1.timestamp }
    }
    
    /// Drop read notifications whose reading happened earlier than `readLifetime`
    /// before `now`. Unread notifications stay regardless of age.
    static func pruneItems(
        _ items: [AppNotification],
        now: Date = Date(),
        readLifetime: TimeInterval = readLifetime
    ) -> [AppNotification] {
        items.filter { item in
            guard item.isRead, let readAt = item.readAt else { return true }
            return now.timeIntervalSince(readAt) < readLifetime
        }
    }
    
    func add(_ notification: AppNotification) {
        notifications.insert(notification, at: 0)
        if !notification.isRead {
            unreadCount += 1
        }
        // Enforce max limit
        if notifications.count > maxNotifications {
            notifications = Array(notifications.prefix(maxNotifications))
        }
    }
    
    func markAsRead(_ id: String) {
        guard let index = notifications.firstIndex(where: { $0.id == id }),
              !notifications[index].isRead else { return }
        notifications[index].isRead = true
        notifications[index].readAt = Date()
        unreadCount = max(0, unreadCount - 1)
    }
    
    private func pruneExpiredRead() {
        let before = notifications.count
        notifications = Self.pruneItems(notifications)
        if notifications.count != before {
            objectWillChange.send()
        }
    }
    
    private func startPruneTimer() {
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.pruneExpiredRead()
        }
    }
    
    func markAllAsRead() {
        for index in notifications.indices {
            notifications[index].isRead = true
        }
        unreadCount = 0
    }
    
    func remove(_ id: String) {
        if let index = notifications.firstIndex(where: { $0.id == id }) {
            if !notifications[index].isRead {
                unreadCount = max(0, unreadCount - 1)
            }
            notifications.remove(at: index)
        }
    }
    
    func clearAll() {
        notifications.removeAll()
        unreadCount = 0
    }
    
    // MARK: - Convenience Methods
    
    func info(title: String, message: String, action: NotificationAction? = nil) {
        add(AppNotification(title: title, message: message, type: .info, action: action))
    }
    
    func success(title: String, message: String, action: NotificationAction? = nil) {
        add(AppNotification(title: title, message: message, type: .success, action: action))
    }
    
    func warning(title: String, message: String, action: NotificationAction? = nil) {
        add(AppNotification(title: title, message: message, type: .warning, action: action))
    }
    
    func error(title: String, message: String, action: NotificationAction? = nil) {
        add(AppNotification(title: title, message: message, type: .error, action: action))
    }
    
    // MARK: - Task Completion
    
    func taskCompleted(sessionTitle: String, sessionID: String) {
        success(
            title: L.t(AppLocalizationKey.locTaskComplete),
            message: L.t(AppLocalizationKey.locTaskCompleteMessage, sessionTitle),
            action: .openSession(sessionID)
        )
    }
    
    func generationStopped() {
        info(
            title: L.t(AppLocalizationKey.locGenerationStopped),
            message: L.t(AppLocalizationKey.locResponseStopped)
        )
    }
    
    func gitOperationComplete(operation: String, details: String) {
        success(
            title: L.t(AppLocalizationKey.locGitOperation, operation),
            message: details,
            action: .openGit
        )
    }
    
    func serverDisconnected() {
        warning(
            title: L.t(AppLocalizationKey.locServerDisconnected),
            message: L.t(AppLocalizationKey.locLocalAgentConnectionLost)
        )
    }
    
    func serverConnected() {
        success(
            title: L.t(AppLocalizationKey.locServerConnected),
            message: L.t(AppLocalizationKey.locConnectedLocalAgent)
        )
    }
    
    func sessionBusy() {
        warning(
            title: L.t(AppLocalizationKey.locSessionBusy),
            message: L.t(AppLocalizationKey.locSessionBusyMessage)
        )
    }
}
