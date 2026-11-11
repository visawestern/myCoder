import SwiftUI
import AppKit
struct SidebarFooterView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.9), Color.orange.opacity(0.65)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)
                Text(appState.userInitials)
                    .interfaceFont(size: 11, weight: .semibold)
                    .foregroundColor(.white)
            }
            
            Text(appState.userDisplayName)
                .interfaceFont(size: 12, weight: .medium)
                .foregroundColor(Color.mimo.textPrimary)
                .lineLimit(1)
            
            Spacer()
            
            Button(action: { appState.showNotifications = true }) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell")
                        .interfaceFont(size: 14)
                        .foregroundColor(Color.mimo.textSecondary)
                    
                    if appState.notificationService.unreadCount > 0 {
                        Text("\(appState.notificationService.unreadCount)")
                            .interfaceFont(size: 9, weight: .bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.mimo.error)
                            .clipShape(Capsule())
                            .offset(x: 6, y: -6)
                    }
                }
            }
            .buttonStyle(HandCursorButtonStyle())
            .help(L.t("Notifications (%d unread)", appState.notificationService.unreadCount))
            
            Button(action: { appState.openSettings() }) {
                Image(systemName: "gearshape")
                    .interfaceFont(size: 14)
                    .foregroundColor(Color.mimo.textSecondary)
            }
            .buttonStyle(HandCursorButtonStyle())
            .help(L.t("Settings"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.mimo.backgroundAlt)
        .overlay(
            Rectangle()
                .fill(Color.mimo.border)
                .frame(height: 1),
            alignment: .top
        )
    }
}

struct NotificationsSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(L.t(AppLocalizationKey.locNotifications1))
                    .interfaceFont(size: 18, weight: .semibold)
                    .foregroundColor(Color.mimo.textPrimary)
                Spacer()
                if appState.notificationService.unreadCount > 0 {
                    Button(L.t(AppLocalizationKey.locMarkAllRead)) {
                        appState.notificationService.markAllAsRead()
                    }
                    .buttonStyle(HandCursorButtonStyle())
                    .interfaceFont(size: 12)
                    .foregroundColor(Color.mimo.brand)
                }
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color.mimo.textMuted)
                }
                .buttonStyle(HandCursorButtonStyle())
            }
            .padding(20)
            
            Divider()
                .padding(.horizontal, 12)
            
            if appState.notificationService.notifications.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "bell.slash")
                        .interfaceFont(size: 32)
                        .foregroundColor(Color.mimo.textMuted.opacity(0.5))
                    Text(L.t(AppLocalizationKey.locNotifications))
                        .interfaceFont(size: 14)
                        .foregroundColor(Color.mimo.textSecondary)
                    Text(L.t(AppLocalizationKey.locTaskCompletionsAndSystemAlertsWillAppearHere))
                        .interfaceFont(size: 12)
                        .foregroundColor(Color.mimo.textMuted)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(appState.notificationService.sortedNotifications) { notification in
                            NotificationRow(notification: notification)
                                .environmentObject(appState)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(width: 380, height: 400)
        .background(Color.mimo.background)
    }
}

struct NotificationRow: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let notification: AppNotification
    /// Guards against a host delivering both the row tap and the inner action
    /// button for the same click, which would route (and scroll) twice.
    @State private var lastRoutedAt = Date.distantPast
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: notification.type.icon)
                .interfaceFont(size: 14)
                .foregroundColor(iconColor)
                .frame(width: 18)
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(notification.title)
                        .interfaceFont(size: 12, weight: .semibold)
                        .foregroundColor(notification.isRead ? Color.mimo.textMuted : Color.mimo.textPrimary)
                    Spacer()
                    if !notification.isRead {
                        Circle()
                            .fill(Color.mimo.brand)
                            .frame(width: 7, height: 7)
                    }
                    Text(timeAgo(notification.timestamp))
                        .interfaceFont(size: 10)
                        .foregroundColor(notification.isRead ? Color.mimo.textMuted.opacity(0.6) : Color.mimo.textMuted)
                }
                Text(notification.message)
                    .interfaceFont(size: 11)
                    .foregroundColor(notification.isRead ? Color.mimo.textMuted.opacity(0.6) : Color.mimo.textSecondary)
                    .lineLimit(2)
                
                if let action = notification.action {
                    Button(action: { handleAction(action) }) {
                        Text(actionLabel(action))
                            .interfaceFont(size: 11, weight: .medium)
                    }
                    .buttonStyle(HandCursorButtonStyle())
                    .foregroundColor(Color.mimo.brand)
                    .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            appState.notificationService.markAsRead(notification.id)
            // Tapping the alert body is the same intent as its action button:
            // open the chat (and the exact tool call, when anchored).
            if let action = notification.action {
                handleAction(action)
            }
        }
        .background(
            notification.isRead
                ? Color.clear
                : Color.mimo.brand.opacity(0.04)
        )
        
        Divider()
            .padding(.leading, 42)
    }
    
    private var iconColor: Color {
        let color: Color
        switch notification.type {
        case .info: color = Color.mimo.brand
        case .success: color = Color.mimo.success
        case .warning: color = Color.mimo.warning
        case .error: color = Color.mimo.error
        }
        return notification.isRead ? color.opacity(0.4) : color
    }
    
    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
    
    private func actionLabel(_ action: NotificationAction) -> String {
        switch action {
        case .openSession: return "Open Session"
        case .openMessage: return "Open tool call"
        case .openSettings: return "Open Settings"
        case .openGit: return "View Changes"
        case .custom(let id): return id
        }
    }
    
    private func handleAction(_ action: NotificationAction) {
        let now = Date()
        guard now.timeIntervalSince(lastRoutedAt) > 0.3 else { return }
        lastRoutedAt = now
        // Child buttons do not reliably propagate the row tap gesture on every
        // macOS SwiftUI host, so action routing explicitly marks the item read.
        appState.notificationService.markAsRead(notification.id)
        let sessionWasFound: Bool
        switch action {
        case .openSession(let sessionID):
            guard let session = appState.sessionForNavigation(id: sessionID) else {
                return
            }
            appState.selectSession(session)
            sessionWasFound = true
        case .openMessage(let sessionID, let messageID):
            // Open the chat AND ask the panel to scroll to the message that
            // raised the alert — opening at the newest message hid the card.
            guard let session = appState.sessionForNavigation(id: sessionID) else {
                return
            }
            appState.selectSession(session)
            appState.requestMessageFocus(sessionID: sessionID, messageID: messageID)
            sessionWasFound = true
        case .openSettings:
            appState.openSettings()
            sessionWasFound = false
        case .openGit:
            appState.showGoal = true
            sessionWasFound = false
        case .custom:
            sessionWasFound = false
        }
        if NotificationActionRoutingLogic.shouldDismissSheet(
            after: action,
            sessionWasFound: sessionWasFound
        ) {
            dismiss()
        }
    }
}
