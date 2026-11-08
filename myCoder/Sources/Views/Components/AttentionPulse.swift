import SwiftUI
import Foundation

/// Мигающая точка-индикатор «звоночка» (директива 2026-11-09):
/// перед надписью чата/проекта пульсирует кружок, меняя цвет
/// с зелёного на красный, пока элемент ждёт решения пользователя.
struct AttentionBlinkDot: View {
    @State private var isGreen = true

    var body: some View {
        Circle()
            .fill(isGreen ? Color.mimo.success : Color.mimo.error)
            .frame(width: 8, height: 8)
            .task {
                while !Task.isCancelled {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        isGreen.toggle()
                    }
                    try? await Task.sleep(for: .milliseconds(450))
                }
            }
            .help(L.t(AppLocalizationKey.locGoalNoneInChat))
            .accessibilityLabel("attention")
    }
}

/// Единое уведомление «внимание изменилось» (одобрения инструментов и т.п.),
/// чтобы строки сайдбара перечитывали свои «звоночки».
enum SidebarAttentionNotification {
    static let changed = Notification.Name("myCoderAttentionChanged")

    static func post() {
        NotificationCenter.default.post(name: changed, object: nil)
    }
}
