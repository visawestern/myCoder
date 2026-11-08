import SwiftUI
import Foundation

/// Моргающая подсветка «звоночка»: пока элемент требует решения пользователя,
/// его фон пульсирует тёплым цветом (директива 2026-11-09).
/// Активируется только когда `active == true`.
struct AttentionPulseModifier: ViewModifier {
    let active: Bool
    @State private var pulsePhase = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.mimo.warning.opacity(pulsePhase ? 0.08 : 0.30))
            )
            .task(id: active) {
                guard active else {
                    pulsePhase = false
                    return
                }
                // Моргание: фаза переключается каждые ~0.65 c, пока активно.
                while !Task.isCancelled {
                    withAnimation(.easeInOut(duration: 0.55)) {
                        pulsePhase.toggle()
                    }
                    try? await Task.sleep(for: .milliseconds(650))
                }
            }
    }
}

extension View {
    func attentionPulse(active: Bool) -> some View {
        modifier(AttentionPulseModifier(active: active))
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
