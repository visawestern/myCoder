import SwiftUI

extension SpecWizardContent {
    // MARK: Building blocks

    func card<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .interfaceFont(size: 12)
                    .foregroundColor(Color.mimo.textSecondary)
                Text(title)
                    .interfaceFont(size: 13, weight: .semibold)
                    .foregroundColor(Color.mimo.textPrimary)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.mimo.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.mimo.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    func primaryButton(_ title: String, icon: String, isBusy: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isBusy {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.7)
                        .tint(.white)
                } else {
                    Image(systemName: icon)
                        .interfaceFont(size: 10, weight: .semibold)
                }
                Text(isBusy ? L.t("Working…") : title)
                    .interfaceFont(size: 12, weight: .semibold)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(Color.mimo.brand)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(HandCursorButtonStyle())
        .foregroundColor(.white)
        .opacity(session.isLoading ? 0.55 : 1)
    }
}
