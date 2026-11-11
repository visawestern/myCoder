import Foundation
import Testing
@testable import myCoder

/// Read notifications must go gray and disappear one hour after they were
/// read (user directive 2026-10-29: "прочитанные уведомления делай серым
/// цветом и через час убирай из уведомлений").
@MainActor
@Suite("Старение уведомлений")
struct NotificationAgingTests {

    private func notification(isRead: Bool, readAt: Date? = nil, createdAt: Date = Date()) -> AppNotification {
        AppNotification(
            title: "t",
            message: "m",
            timestamp: createdAt,
            isRead: isRead,
            readAt: readAt
        )
    }

    @Test("Прочитанное старше часа отсеивается")
    func readOlderThanHourIsPruned() {
        let now = Date()
        let oldRead = notification(isRead: true, readAt: now.addingTimeInterval(-3700))
        let items = [oldRead]
        let result = NotificationService.pruneItems(items, now: now)
        #expect(result.isEmpty)
    }

    @Test("Прочитанное младше часа остаётся")
    func readNewerThanHourStays() {
        let now = Date()
        let freshRead = notification(isRead: true, readAt: now.addingTimeInterval(-60))
        let result = NotificationService.pruneItems([freshRead], now: now)
        #expect(result.count == 1)
    }

    @Test("Непрочитанное остаётся независимо от возраста")
    func unreadStaysRegardlessOfAge() {
        let now = Date()
        let oldUnread = notification(isRead: false, createdAt: now.addingTimeInterval(-7200))
        let result = NotificationService.pruneItems([oldUnread], now: now)
        #expect(result.count == 1)
    }

    @Test("Смешанный список: уходит только старое прочитанное")
    func mixedListPrunesOnlyOldRead() {
        let now = Date()
        let oldRead = notification(isRead: true, readAt: now.addingTimeInterval(-7200))
        let freshRead = notification(isRead: true, readAt: now.addingTimeInterval(-30))
        let unread = notification(isRead: false, createdAt: now.addingTimeInterval(-7200))
        let result = NotificationService.pruneItems([oldRead, freshRead, unread], now: now)
        #expect(result == [freshRead, unread])
    }

    @Test("markAsRead фиксирует время прочтения")
    func markAsReadStampsReadAt() {
        let service = NotificationService()
        let note = notification(isRead: false)
        service.add(note)
        let id = note.id
        service.markAsRead(id)
        #expect(service.notifications.first?.isRead == true)
        #expect(service.notifications.first?.readAt != nil)
    }
}
