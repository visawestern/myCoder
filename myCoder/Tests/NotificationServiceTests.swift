import Testing
import Foundation
@testable import myCoder

@Suite("Notification Service")
struct NotificationServiceTests {
    init() { LocalizationRuntime.currentLanguage = .english }
    
    // MARK: - Basic Operations
    
    @Test("Empty service has no notifications")
    func emptyService() {
        let service = NotificationService()
        #expect(service.notifications.isEmpty)
        #expect(service.unreadCount == 0)
        #expect(service.sortedNotifications.isEmpty)
    }
    
    @Test("Adding notification increases count")
    func addNotification() {
        let service = NotificationService()
        service.add(AppNotification(title: "Test", message: "Message"))
        
        #expect(service.notifications.count == 1)
        #expect(service.unreadCount == 1)
    }
    
    @Test("Adding read notification does not increase unread count")
    func addReadNotification() {
        let service = NotificationService()
        service.add(AppNotification(title: "Test", message: "Message", isRead: true))
        
        #expect(service.notifications.count == 1)
        #expect(service.unreadCount == 0)
    }
    
    @Test("Notifications are sorted by timestamp descending")
    func sortedByTimestamp() {
        let service = NotificationService()
        let old = AppNotification(title: "Old", message: "", timestamp: Date(timeIntervalSinceNow: -100))
        let new = AppNotification(title: "New", message: "", timestamp: Date(timeIntervalSinceNow: -10))
        
        service.add(old)
        service.add(new)
        
        #expect(service.sortedNotifications.first?.title == "New")
        #expect(service.sortedNotifications.last?.title == "Old")
    }
    
    @Test("Marking notification as read updates unread count")
    func markAsRead() {
        let service = NotificationService()
        let notif = AppNotification(title: "Test", message: "Msg")
        service.add(notif)
        
        #expect(service.unreadCount == 1)
        service.markAsRead(notif.id)
        #expect(service.unreadCount == 0)
        #expect(service.notifications.first?.isRead == true)
    }
    
    @Test("Marking already read notification does not change unread count")
    func markAlreadyRead() {
        let service = NotificationService()
        let notif = AppNotification(title: "Test", message: "Msg", isRead: true)
        service.add(notif)
        
        #expect(service.unreadCount == 0)
        service.markAsRead(notif.id)  // No effect
        #expect(service.unreadCount == 0)
    }
    
    @Test("Marking unknown notification does nothing")
    func markUnknown() {
        let service = NotificationService()
        service.markAsRead("nonexistent")
        #expect(service.unreadCount == 0)
    }
    
    @Test("Mark all as read clears unread count")
    func markAllAsRead() {
        let service = NotificationService()
        service.add(AppNotification(title: "A", message: ""))
        service.add(AppNotification(title: "B", message: ""))
        service.add(AppNotification(title: "C", message: ""))
        
        #expect(service.unreadCount == 3)
        service.markAllAsRead()
        #expect(service.unreadCount == 0)
        #expect(service.notifications.allSatisfy { $0.isRead })
    }
    
    @Test("Removing notification decreases unread count")
    func removeNotification() {
        let service = NotificationService()
        let notif = AppNotification(title: "Test", message: "")
        service.add(notif)
        
        #expect(service.unreadCount == 1)
        service.remove(notif.id)
        #expect(service.notifications.isEmpty)
        #expect(service.unreadCount == 0)
    }
    
    @Test("Removing read notification does not affect unread count")
    func removeReadNotification() {
        let service = NotificationService()
        let read = AppNotification(title: "Read", message: "", isRead: true)
        let unread = AppNotification(title: "Unread", message: "")
        service.add(read)
        service.add(unread)
        
        #expect(service.unreadCount == 1)
        service.remove(read.id)
        #expect(service.notifications.count == 1)
        #expect(service.unreadCount == 1)
    }
    
    @Test("Clear all removes everything")
    func clearAll() {
        let service = NotificationService()
        service.add(AppNotification(title: "A", message: ""))
        service.add(AppNotification(title: "B", message: ""))
        
        service.clearAll()
        #expect(service.notifications.isEmpty)
        #expect(service.unreadCount == 0)
    }
    
    @Test("Max notifications limit is enforced")
    func maxLimit() {
        let service = NotificationService()
        for i in 0..<55 {
            service.add(AppNotification(title: "N\(i)", message: ""))
        }
        #expect(service.notifications.count <= 50)
    }
    
    // MARK: - Convenience Methods
    
    @Test("Info convenience creates correct type")
    func infoConvenience() {
        let service = NotificationService()
        service.info(title: "Info", message: "Info message")
        
        #expect(service.notifications.first?.type == .info)
        #expect(service.notifications.first?.title == "Info")
    }
    
    @Test("Success convenience creates correct type")
    func successConvenience() {
        let service = NotificationService()
        service.success(title: "Done", message: "Completed")
        
        #expect(service.notifications.first?.type == .success)
    }
    
    @Test("Warning convenience creates correct type")
    func warningConvenience() {
        let service = NotificationService()
        service.warning(title: "Caution", message: "Something")
        
        #expect(service.notifications.first?.type == .warning)
    }
    
    @Test("Error convenience creates correct type")
    func errorConvenience() {
        let service = NotificationService()
        service.error(title: "Error", message: "Failed")
        
        #expect(service.notifications.first?.type == .error)
    }
    
    // MARK: - Action Handling
    
    @Test("Task completed notification creates success type")
    func taskCompletedNotification() {
        let service = NotificationService()
        service.taskCompleted(sessionTitle: "Test task", sessionID: "s1")
        
        #expect(service.notifications.first?.type == .success)
        #expect(service.notifications.first?.title == "Task Complete")
        #expect(service.notifications.first?.message.contains("Test task") == true)
    }
    
    @Test("Generation stopped notification creates info type")
    func generationStoppedNotification() {
        let service = NotificationService()
        service.generationStopped()
        
        #expect(service.notifications.first?.type == .info)
        #expect(service.notifications.first?.title == "Generation stopped")
    }
    
    @Test("Git operation notification creates success type")
    func gitOperationNotification() {
        let service = NotificationService()
        service.gitOperationComplete(operation: "Commit", details: "Initial commit")
        
        #expect(service.notifications.first?.type == .success)
        #expect(service.notifications.first?.title == "Git Commit")
        #expect(service.notifications.first?.action == .openGit)
    }
    
    @Test("Server disconnected notification creates warning type")
    func serverDisconnectedNotification() {
        let service = NotificationService()
        service.serverDisconnected()
        
        #expect(service.notifications.first?.type == .warning)
        #expect(service.notifications.first?.title == "Server Disconnected")
    }
    
    @Test("Server connected notification creates success type")
    func serverConnectedNotification() {
        let service = NotificationService()
        service.serverConnected()
        
        #expect(service.notifications.first?.type == .success)
        #expect(service.notifications.first?.title == "Server Connected")
    }
    
    @Test("Session busy notification creates warning type")
    func sessionBusyNotification() {
        let service = NotificationService()
        service.sessionBusy()
        
        #expect(service.notifications.first?.type == .warning)
        #expect(service.notifications.first?.title == "Session Busy")
    }
    
    // MARK: - NotificationType
    
    @Test("NotificationType icons are unique")
    func typeIcons() {
        #expect(NotificationType.info.icon == "info.circle")
        #expect(NotificationType.success.icon == "checkmark.circle")
        #expect(NotificationType.warning.icon == "exclamationmark.triangle")
        #expect(NotificationType.error.icon == "xmark.circle")
    }
    
    // MARK: - Thread Safety
    
    @Test("Concurrent notifications maintain order")
    func concurrentAdditions() {
        let service = NotificationService()
        let group = DispatchGroup()
        
        for i in 0..<10 {
            DispatchQueue.global().async(group: group) {
                service.add(AppNotification(title: "N\(i)", message: ""))
            }
        }
        
        group.wait()
        #expect(service.notifications.count <= 10)
    }
}


@Suite("myCoder Auto Free switch notifications")
struct MyCoderAutoFreeNotificationTests {
    init() { LocalizationRuntime.currentLanguage = .english }
    @Test("Rate-limit switch creates a prominent error notification")
    func rateLimitMessage() {
        let notification = MyCoderAutoFreeNotificationLogic.make(userInfo: [
            "fromModel": "big-pickle",
            "toModel": "deepseek-v4-flash-free",
            "reason": "rate limit"
        ])

        #expect(notification.type == .error)
        #expect(notification.title == "Free model rate limited")
        #expect(notification.message.contains("big-pickle"))
        #expect(notification.message.contains("deepseek-v4-flash-free"))
        #expect(notification.message.contains("rate limit"))
    }

    @Test("Non-rate-limit switch remains distinguishable")
    func genericSwitchMessage() {
        let notification = MyCoderAutoFreeNotificationLogic.make(userInfo: [
            "fromModel": "big-pickle",
            "toModel": "hy3-free",
            "reason": "model unavailable"
        ])

        #expect(notification.type == .warning)
        #expect(notification.title == "Free model switched")
        #expect(notification.message.contains("model unavailable"))
        #expect(notification.message.contains("hy3-free"))
    }
}
