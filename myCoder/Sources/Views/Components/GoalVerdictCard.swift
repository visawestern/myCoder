import SwiftUI

/// Вердикт проверки цели в чате: компактный чип со статусом, по клику —
/// спойлер с конкретными невыполненными пунктами и причиной.
///
/// Сырой JSON (`{"complete":false,"notDone":[…]}`) в пузыре читать
/// невозможно; это тот же вердикт, но в понятном виде.
struct GoalVerdictCard: View {
    let presentation: GoalVerdictPresentationLogic.Presentation
    @State private var expanded = false

    private var tint: Color {
        presentation.complete ? Color.green : Color.orange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: presentation.complete
                          ? "checkmark.seal.fill"
                          : "exclamationmark.triangle.fill")
                        .interfaceFont(size: 13)
                        .foregroundColor(tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(presentation.title)
                            .interfaceFont(size: 12, weight: .semibold)
                            .foregroundColor(Color.mimo.textPrimary)
                        Text(presentation.subtitle)
                            .interfaceFont(size: 11)
                            .foregroundColor(Color.mimo.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .interfaceFont(size: 9, weight: .semibold)
                        .foregroundColor(Color.mimo.textMuted)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(tint.opacity(0.14))
                )
                .overlay(
                    Capsule().stroke(tint.opacity(0.45), lineWidth: 0.8)
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(expanded ? "Свернуть вердикт" : "Показать, что не готово")

            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    if !presentation.notDone.isEmpty {
                        Text("Не готово")
                            .interfaceFont(size: 11, weight: .semibold)
                            .foregroundColor(Color.mimo.textSecondary)
                        ForEach(Array(presentation.notDone.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•")
                                    .interfaceFont(size: 11)
                                    .foregroundColor(tint)
                                Text(item)
                                    .interfaceFont(size: 11)
                                    .foregroundColor(Color.mimo.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    if !presentation.reason.isEmpty {
                        Text("Причина")
                            .interfaceFont(size: 11, weight: .semibold)
                            .foregroundColor(Color.mimo.textSecondary)
                            .padding(.top, presentation.notDone.isEmpty ? 0 : 2)
                        Text(presentation.reason)
                            .interfaceFont(size: 11)
                            .foregroundColor(Color.mimo.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.mimo.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.mimo.border.opacity(0.6), lineWidth: 0.5)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
