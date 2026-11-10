import SwiftUI
struct MessageActionButton: View {
    let icon: String
    let tooltip: String
    var isActive: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .interfaceFont(size: 11)
                .foregroundColor(isActive ? Color.mimo.success : Color.mimo.textMuted)
                .frame(width: 24, height: 24)
                .background(isHovering ? Color.mimo.surfaceHover : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(HandCursorButtonStyle())
        .onHover { isHovering = $0 }
        .help(tooltip)
    }
}

struct FileChangeSummaryRow: View {
    let path: String
    let additions: Int
    let deletions: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .interfaceFont(size: 12)
                .foregroundColor(Color.mimo.textMuted)
            Text((path as NSString).lastPathComponent)
                .interfaceFont(size: 12, design: .monospaced)
                .foregroundColor(Color.mimo.textPrimary)
                .lineLimit(1)
            Spacer()
            Text("+\(additions)")
                .interfaceFont(size: 11, weight: .medium)
                .foregroundColor(Color.mimo.success)
            Text("-\(deletions)")
                .interfaceFont(size: 11, weight: .medium)
                .foregroundColor(Color.mimo.error)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.mimo.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Interactive Allow/Deny card for a web-agent tool that needs user approval
/// before execution. The driver is blocked awaiting the verdict; the card
/// resolves the pending request through `webToolApprovalResolved` and the
/// chat panel forwards the answer to the driver's approval mailbox.

struct WebToolApprovalCardView: View {
    let approvalID: String
    let tool: String
    let message: String
    var notificationName: Notification.Name = .webToolApprovalResolved

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield")
                    .interfaceFont(size: 14)
                    .foregroundColor(Color.mimo.warning)
                Text("myCoder wants to run a restricted tool")
                    .interfaceFont(size: 13, weight: .semibold)
                    .foregroundColor(Color.mimo.textPrimary)
                Spacer()
            }
            Text(message)
                .interfaceFont(size: 12)
                .foregroundColor(Color.mimo.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            HStack(spacing: 10) {
                Button {
                    resolve(approved: true)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark")
                            .interfaceFont(size: 11, weight: .bold)
                        Text("Allow")
                            .interfaceFont(size: 12, weight: .semibold)
                    }
                    .foregroundColor(Color.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.mimo.success)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(HandCursorButtonStyle())
                .accessibilityIdentifier("toolApproval.allow")
                Button {
                    resolve(approved: false)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "xmark")
                            .interfaceFont(size: 11, weight: .bold)
                        Text("Deny")
                            .interfaceFont(size: 12, weight: .semibold)
                    }
                    .foregroundColor(Color.mimo.error)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.mimo.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.mimo.error, lineWidth: 1)
                    )
                }
                .buttonStyle(HandCursorButtonStyle())
                .accessibilityIdentifier("toolApproval.deny")
                Spacer()
            }
        }
        .padding(12)
        .background(Color.mimo.surface.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.mimo.warning.opacity(0.6), lineWidth: 1)
        )
    }

    private func resolve(approved: Bool) {
        // Resolve on the next run-loop turn: the Combine receiver resumes
        // the waiting turn and mutates MessageStore. Doing that inline from
        // the button action can re-enter SwiftUI's update and spin.
        let name = notificationName
        let id = approvalID
        let toolName = tool
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: name,
                object: nil,
                userInfo: [
                    "approvalID": id,
                    "tool": toolName,
                    "approved": approved
                ]
            )
        }
    }
}

/// The full point context that was compiled locally for a message.
/// Shows the text as-is (no summary) with a copy button.

struct CompiledContextSheet: View {
    let text: String
    /// Показывается, когда `text` пуст — честная причина, почему контекст
    /// не собран (первый промпт, чат без проекта, нет соответствий, ошибка).
    var fallback: String? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var displayText: String {
        if !text.isEmpty { return text }
        return fallback ?? "Контекст не собран."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(L.t(AppLocalizationKey.locCompiledContextTitle))
                    .interfaceFont(size: 13, weight: .semibold)
                    .foregroundColor(Color.mimo.textPrimary)
                Spacer(minLength: 8)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(displayText, forType: .string)
                    copied = true
                } label: {
                    Label(L.t(AppLocalizationKey.locCopyAll), systemImage: "doc.on.doc")
                        .interfaceFont(size: 11)
                }
                .buttonStyle(HandCursorButtonStyle())
                .foregroundColor(copied ? Color.mimo.success : Color.mimo.textSecondary)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .interfaceFont(size: 11, weight: .semibold)
                }
                .buttonStyle(HandCursorButtonStyle())
                .foregroundColor(Color.mimo.textSecondary)
            }

            TabView {
                ForEach(Array(TurnPresentation.inspectionTabs(displayText).enumerated()), id: \.offset) { index, section in
                ScrollView {
                Text(section.body)
                    .interfaceFont(size: 11, design: .monospaced)
                    .foregroundColor(Color.mimo.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
                .tabItem {
                    if index == 0 {
                        // Первая вкладка «Итоговый промпт» — зелёная и открыта
                        // по умолчанию (директива 2026-11-08).
                        Label(section.title, systemImage: "doc.text.fill")
                            .foregroundColor(Color.mimo.success)
                    } else {
                        Text(section.title)
                    }
                }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(10)
            .background(Color.mimo.codeBg)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.mimo.border.opacity(0.55), lineWidth: 1)
            )
        }
        .padding(16)
        .frame(minWidth: 920, minHeight: 540)
        .background(Color.mimo.background)
    }
}

/// Telegram-style sender line for a message: send time + small provider/model/
/// parameter chips that open a metadata card on tap (user directive
/// 2026-10-29, §15.5).

struct MessageSendInfoFooter: View {
    let info: MessageSendInfo

    @State private var showCard = false

    private var isCustomized: Bool {
        info.temperature != nil || info.topP != nil || info.maxTokens != nil
            || !(info.systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            || info.variant != nil
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(info.sentAt.formatted(date: .omitted, time: .shortened))
                .interfaceFont(size: 10)
                .foregroundColor(Color.mimo.textMuted)

            if let provider = info.providerID, !provider.isEmpty {
                chip(icon: "network", label: provider, tooltip: "Provider: \(provider)")
            }
            if let model = info.modelID, !model.isEmpty {
                chip(icon: "cpu", label: model, tooltip: "Model: \(model)")
            }
            if isCustomized {
                chip(icon: "slider.horizontal.3", label: "params", tooltip: "Send parameters")
            }
        }
        .padding(.top, 2)
    }

    private func chip(icon: String, label: String, tooltip: String) -> some View {
        Button {
            showCard = true
        } label: {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .interfaceFont(size: 9)
                Text(label)
                    .interfaceFont(size: 10, design: .monospaced)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.mimo.surfaceHover.opacity(0.6))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color.mimo.border.opacity(0.6), lineWidth: 1)
            )
            .foregroundColor(Color.mimo.textSecondary)
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .popover(isPresented: $showCard) {
            MessageSendInfoCard(info: info)
        }
    }
}

struct MessageSendInfoCard: View {
    let info: MessageSendInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Message details")
                .interfaceFont(size: 13, weight: .semibold)
                .foregroundColor(Color.mimo.textPrimary)
            row("Sent", info.sentAt.formatted(date: .abbreviated, time: .standard))
            row("Provider", info.providerID ?? "—")
            row("Model", info.modelID ?? "—")
            if let variant = info.variant { row("Variant", variant) }
            if let temperature = info.temperature { row("Temperature", String(format: "%.2f", temperature)) }
            if let topP = info.topP { row("Top-p", String(format: "%.2f", topP)) }
            if let maxTokens = info.maxTokens { row("Max tokens", "\(maxTokens)") }
            if let system = info.systemPrompt, !system.isEmpty {
                row("System", system)
            }
        }
        .padding(14)
        .frame(minWidth: 260)
        .background(Color.mimo.background)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .interfaceFont(size: 11, weight: .medium)
                .foregroundColor(Color.mimo.textMuted)
                .frame(width: 78, alignment: .leading)
            Text(value)
                .interfaceFont(size: 11)
                .foregroundColor(Color.mimo.textSecondary)
                .textSelection(.enabled)
                .lineLimit(4)
            Spacer(minLength: 0)
        }
    }
}
