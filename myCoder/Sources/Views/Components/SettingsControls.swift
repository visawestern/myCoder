import SwiftUI

struct MiMoTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .interfaceFont(size: 13)
            .foregroundColor(Color.mimo.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.mimo.input)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.mimo.inputBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

extension View {
    func zcodeTextFieldStyle() -> some View {
        textFieldStyle(MiMoTextFieldStyle())
    }
}

struct SettingsMenuLabel<Content: View>: View {
    let title: String
    @ViewBuilder let menuContent: () -> Content
    
    var body: some View {
        Menu {
            menuContent()
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .interfaceFont(size: 13, weight: .medium)
                    .foregroundColor(Color.mimo.textPrimary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.mimo.controlBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.mimo.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.borderlessButton)
    }
}

/// Premium empty state for settings cards: soft icon badge, title, hint and
/// an optional call-to-action, centered inside the card.
struct SettingsCardEmptyState: View {
    let icon: String
    let title: String
    let hint: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.mimo.brand.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .interfaceFont(size: 17)
                    .foregroundColor(Color.mimo.brand)
            }

            Text(title)
                .interfaceFont(size: 13, weight: .semibold)
                .foregroundColor(Color.mimo.textPrimary)

            Text(hint)
                .interfaceFont(size: 11)
                .foregroundColor(Color.mimo.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .interfaceFont(size: 12, weight: .medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.mimo.brand)
                        .clipShape(Capsule())
                }
                .buttonStyle(HandCursorButtonStyle())
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension View {
    /// Stretches a settings card to fill the row height so side-by-side cards
    /// stay equal-height with no dead gaps.
    func settingsCardFrame() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct SettingsSegmentButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .interfaceFont(size: 12, weight: isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? Color.mimo.textPrimary : Color.mimo.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.mimo.controlBackground : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.mimo.border : Color.clear, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(HandCursorButtonStyle())
    }
}
