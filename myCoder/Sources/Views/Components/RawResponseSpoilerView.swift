import SwiftUI

/// Debug-спойлер «Сырой ответ»: показывает сырые ответы сервера (SSE
/// payload'ы / JSON-тела) в порядке их прихода. Никогда не виден, пока
/// пользователь его не раскроет (user request 2026-10-30).
struct RawResponseSpoilerView: View {
    let rawEvents: [String]

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            }) {
                HStack(spacing: 5) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .interfaceFont(size: 10, weight: .semibold)
                    Text("Сырой ответ (\(rawEvents.count) событий)")
                        .interfaceFont(size: 11, weight: .medium)
                    Spacer(minLength: 0)
                }
                .foregroundColor(Color.mimo.textMuted)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(rawEvents.enumerated()), id: \.offset) { index, event in
                            Text("#\(index + 1) \(event)")
                                .interfaceFont(size: 10)
                                .foregroundColor(Color.mimo.textSecondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 180)
                .background(Color.mimo.subtleFill)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.mimo.border, lineWidth: 1)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
