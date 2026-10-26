import SwiftUI

/// Label-first inline editor: the value is read-only until the pencil is
/// pressed, then it becomes a text field with an explicit green check and a
/// red cancel. No hidden auto-save and no separate "Save" button.
struct InlineEditableField: View {
    let title: String?
    let value: String
    var placeholder: String = "—"
    var isSecure: Bool = false
    var monospaced: Bool = false
    var fontSize: CGFloat = 11
    var fontWeight: Font.Weight = .regular
    var editValue: String? = nil
    var onCommit: (String) -> Void

    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title, !title.isEmpty {
                Text(title)
                    .interfaceFont(size: 11, weight: .medium)
                    .foregroundColor(Color.mimo.textSecondary)
            }
            HStack(spacing: 6) {
                if isEditing {
                    Group {
                        if isSecure {
                            SecureField(placeholder, text: $draft)
                        } else {
                            TextField(placeholder, text: $draft)
                        }
                    }
                    .textFieldStyle(.plain)
                    .interfaceFont(size: fontSize, weight: fontWeight, design: monospaced ? .monospaced : .default)
                    .foregroundColor(Color.mimo.textPrimary)
                    .focused($focused)
                    .onSubmit(commit)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(Color.mimo.background)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.mimo.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    actionButton("checkmark", color: Color.mimo.success, help: L.t(AppLocalizationKey.locSave), action: commit)
                    actionButton("xmark", color: Color.mimo.error, help: L.t(AppLocalizationKey.locCancel), action: cancel)
                } else {
                    Text(value.isEmpty ? placeholder : value)
                        .interfaceFont(size: fontSize, weight: fontWeight, design: monospaced ? .monospaced : .default)
                        .foregroundColor(value.isEmpty ? Color.mimo.textMuted : Color.mimo.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)

                    Spacer(minLength: 4)

                    actionButton("pencil", color: Color.mimo.textMuted, help: L.t(AppLocalizationKey.locEdit)) {
                        draft = editValue ?? value
                        isEditing = true
                        DispatchQueue.main.async { focused = true }
                    }
                }
            }
        }
    }

    private func actionButton(
        _ systemName: String,
        color: Color,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .interfaceFont(size: 10, weight: .semibold)
                .foregroundColor(color)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(HandCursorButtonStyle())
        .help(help)
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        onCommit(trimmed)
        isEditing = false
        focused = false
    }

    private func cancel() {
        draft = value
        isEditing = false
        focused = false
    }
}

struct InlineEditableTextArea: View {
    let title: String
    let value: String
    var placeholder: String = "—"
    var onCommit: (String) -> Void

    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .interfaceFont(size: 11, weight: .medium)
                .foregroundColor(Color.mimo.textSecondary)
            if isEditing {
                TextEditor(text: $draft)
                    .font(.system(size: 11))
                    .frame(minHeight: 58, maxHeight: 100)
                    .padding(6)
                    .background(Color.mimo.background)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.mimo.border, lineWidth: 1))
                    .focused($focused)
                HStack {
                    Spacer()
                    actionButton("checkmark", color: Color.mimo.success, help: L.t(AppLocalizationKey.locSave)) {
                        onCommit(draft.trimmingCharacters(in: .whitespacesAndNewlines))
                        isEditing = false
                        focused = false
                    }
                    actionButton("xmark", color: Color.mimo.error, help: L.t(AppLocalizationKey.locCancel)) {
                        draft = value
                        isEditing = false
                        focused = false
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 6) {
                    Text(value.isEmpty ? placeholder : value)
                        .interfaceFont(size: 11)
                        .foregroundColor(value.isEmpty ? Color.mimo.textMuted : Color.mimo.textPrimary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                    Spacer(minLength: 4)
                    actionButton("pencil", color: Color.mimo.textMuted, help: L.t(AppLocalizationKey.locEdit)) {
                        draft = value
                        isEditing = true
                        DispatchQueue.main.async { focused = true }
                    }
                }
            }
        }
    }

    private func actionButton(
        _ systemName: String,
        color: Color,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .interfaceFont(size: 10, weight: .semibold)
                .foregroundColor(color)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(HandCursorButtonStyle())
        .help(help)
    }
}
