import SwiftUI

/// In-input command palette overlay (plan Раздел 6 Блок 2). Renders the items
/// from InputDropdownDataSource for the active trigger (/ @ # $), supports
/// keyboard navigation, and inserts the chosen item into the message text.
/// Attach via `.overlay(alignment: .bottomLeading)` above the input field.
struct InputCommandDropdownView: View {
    @Binding var messageText: String
    /// Lazily provides the data context — invoked ONLY when a trigger is active,
    /// so the (filesystem-touching) scan doesn't run on every keystroke
    /// (audit P16 — was called on every input-field body render).
    let contextProvider: () -> InputDropdownDataSource.Context
    /// Called after a selection updates the text (so the field can refocus).
    var onInsert: (() -> Void)? = nil

    @State private var highlighted = 0

    private var trigger: TriggerContext? {
        InputCommandTriggerLogic.detectTrigger(text: messageText, cursorPosition: messageText.count)
    }

    private var items: [CommandDropdownItem] {
        guard let trigger else { return [] }   // no trigger → no context build, no scan
        return InputDropdownDataSource.items(for: trigger, context: contextProvider())
    }

    var body: some View {
        if let trigger, !items.isEmpty {
            let groups = InputDropdownDataSource.grouped(Array(items.prefix(30)))
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(groups, id: \.category) { group in
                            Text(group.category.uppercased())
                                .interfaceFont(size: 10, weight: .semibold)
                                .foregroundColor(Color.mimo.textMuted)
                                .padding(.horizontal, 10)
                                .padding(.top, 8)
                            ForEach(Array(group.items.enumerated()), id: \.element.id) { _, item in
                                dropdownRow(item, trigger: trigger,
                                            isHighlighted: flatIndex(of: item) == highlighted)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 260)
            }
            .background(Color.mimo.surface)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.mimo.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
            .frame(maxWidth: 420)
            .onChange(of: messageText) { _ in
                highlighted = DropdownKeyboardLogic.clamp(highlighted, count: flatItems.count)
            }
            // Arrow-key navigation (macOS 13-compatible), Enter commits.
            .onMoveCommand { direction in
                switch direction {
                case .down: highlighted = DropdownKeyboardLogic.moveDown(current: highlighted, count: flatItems.count)
                case .up: highlighted = DropdownKeyboardLogic.moveUp(current: highlighted, count: flatItems.count)
                default: break
                }
            }
            .background(
                Button("") { commitHighlighted(trigger: trigger) }
                    .keyboardShortcut(.defaultAction)
                    .opacity(0)
            )
        }
    }

    private func commitHighlighted(trigger: TriggerContext) {
        guard let idx = DropdownKeyboardLogic.commitIndex(highlight: highlighted, count: flatItems.count) else { return }
        insert(flatItems[idx], trigger: trigger)
    }

    private var flatItems: [CommandDropdownItem] { Array(items.prefix(30)) }

    private func flatIndex(of item: CommandDropdownItem) -> Int {
        flatItems.firstIndex(where: { $0.id == item.id }) ?? -1
    }

    private func dropdownRow(_ item: CommandDropdownItem, trigger: TriggerContext, isHighlighted: Bool) -> some View {
        Button(action: { insert(item, trigger: trigger) }) {
            HStack(spacing: 8) {
                Image(systemName: item.icon)
                    .interfaceFont(size: 12)
                    .foregroundColor(Color.mimo.brand)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .interfaceFont(size: 13, weight: .medium)
                        .foregroundColor(Color.mimo.textPrimary)
                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .interfaceFont(size: 11)
                            .foregroundColor(Color.mimo.textMuted)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isHighlighted ? Color.mimo.brand.opacity(0.12) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(HandCursorButtonStyle())
        .accessibilityLabel("\(item.title). \(item.subtitle)")
    }

    private func insert(_ item: CommandDropdownItem, trigger: TriggerContext) {
        let result = InputDropdownDataSource.applySelection(item, trigger: trigger, text: messageText)
        messageText = result.text
        if item.kind == .command, let key = item.actionKey {
            SlashCommandRegistry.recordUsage(name: key)
        }
        onInsert?()
    }
}
