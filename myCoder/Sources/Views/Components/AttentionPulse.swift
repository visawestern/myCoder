import SwiftUI
import Foundation

/// Неоновая пульсирующая подсветка НАДПИСИ (директива 2026-11-09): когда
/// элемент требует решения пользователя, его текст начинает светиться
/// неоновым цветом — верхний слой-дубль с размытием и моргающей
/// интенсивностью. Фон не трогается.
struct NeonGlowModifier: ViewModifier {
    let active: Bool
    @State private var phase = false

    func body(content: Content) -> some View {
        content
            .foregroundColor(active ? Color.mimo.warning : nil)
            .overlay {
                if active {
                    content
                        .foregroundColor(Color.mimo.warning)
                        .blur(radius: phase ? 7 : 2)
                        .opacity(0.65)
                        .allowsHitTesting(false)
                }
            }
            .task(id: active) {
                guard active else {
                    phase = false
                    return
                }
                while !Task.isCancelled {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        phase.toggle()
                    }
                    try? await Task.sleep(for: .milliseconds(600))
                }
            }
    }
}

extension View {
    /// Неоновая подсветка текста. `active` — горит ли «звоночек».
    func neonGlow(active: Bool) -> some View {
        modifier(NeonGlowModifier(active: active))
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
