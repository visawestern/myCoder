import SwiftUI

struct CommandsSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchQuery = ""
    @State private var commands: [CommandEntry] = []
    @State private var editor: CommandEditorModel?
    @State private var commandToDelete: CommandEntry?

    private var filtered: [CommandEntry] {
        AgentResourcesLoader.filterEntries(commands, query: searchQuery) { $0.name }
    }

    private var builtIns: [SlashCommand] {
        SlashCommandRegistry.builtInCommands.filter { cmd in
            let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }
            return cmd.name.localizedCaseInsensitiveContains(query)
                || cmd.description.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(L.t(AppLocalizationKey.locCommands))
                .interfaceFont(size: 24, weight: .bold)
                .foregroundColor(Color.mimo.textPrimary)

            Text(L.t(AppLocalizationKey.locCommandsSubtitle))
                .interfaceFont(size: 14)
                .foregroundColor(Color.mimo.textSecondary)

            if !appState.supportsToolcallForSelection {
                Text(L.t(AppLocalizationKey.locToolsUnavailableForTheCurrentModelProvider))
                    .interfaceFont(size: 12)
                    .foregroundColor(Color.mimo.warning)
            }

            TextField(L.t(AppLocalizationKey.locSearchCommands), text: $searchQuery)
                .zcodeTextFieldStyle()

            // Built-in section (read-only; always available).
            Text(L.t(AppLocalizationKey.locBuiltInCommands))
                .interfaceFont(size: 12, weight: .semibold)
                .foregroundColor(Color.mimo.textMuted)
            ForEach(builtIns, id: \.id) { cmd in
                builtInRow(cmd)
            }

            // Custom commands section (full CRUD).
            HStack {
                Text(L.t(AppLocalizationKey.locCustomCommands))
                    .interfaceFont(size: 12, weight: .semibold)
                    .foregroundColor(Color.mimo.textMuted)
                Spacer()
                Button(action: { editor = CommandEditorModel() }) {
                    Label(L.t(AppLocalizationKey.locNewCommand), systemImage: "plus")
                        .interfaceFont(size: 12, weight: .medium)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(L.t(AppLocalizationKey.locNewCommand))
            }

            if filtered.isEmpty {
                settingsEmptyState(L.t(AppLocalizationKey.locNoUserCommands), subtitle: L.t(AppLocalizationKey.locAddCommand))
            } else {
                ForEach(filtered) { command in
                    commandRow(command)
                }
            }
        }
        .onAppear(perform: reload)
        .sheet(item: $editor) { model in
            CommandEditorSheet(model: model, onSaved: { reload() })
        }
        .alert(item: $commandToDelete) { entry in
            Alert(
                title: Text(L.t(AppLocalizationKey.locDeleteCommandConfirmation).replacingOccurrences(of: "{0}", with: entry.name)),
                primaryButton: .destructive(Text(L.t(AppLocalizationKey.locDelete))) {
                    _ = try? CommandFileManager.delete(named: entry.name)
                    reload()
                },
                secondaryButton: .cancel(Text(L.t(AppLocalizationKey.locCancel)))
            )
        }
    }

    private func builtInRow(_ cmd: SlashCommand) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: cmd.icon)
                .interfaceFont(size: 12)
                .foregroundColor(Color.mimo.textMuted)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(cmd.displayName)
                    .interfaceFont(size: 13, weight: .medium)
                    .foregroundColor(Color.mimo.textPrimary)
                Text(cmd.description)
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(L.t(AppLocalizationKey.locBuiltInCommands))
                .interfaceFont(size: 10, weight: .medium)
                .foregroundColor(Color.mimo.textMuted)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.mimo.subtleFill)
                .clipShape(Capsule())
        }
        .padding(12)
        .background(Color.mimo.surface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mimo.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func commandRow(_ command: CommandEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: command.isEnabled ? "terminal" : "terminal.slash")
                .interfaceFont(size: 12)
                .foregroundColor(command.isEnabled ? Color.mimo.textMuted : Color.mimo.textMuted.opacity(0.5))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("/\(command.name)")
                        .interfaceFont(size: 13, weight: .medium)
                        .foregroundColor(command.isEnabled ? Color.mimo.textPrimary : Color.mimo.textSecondary)
                    if command.description.isEmpty == false {
                        Text(command.description)
                            .interfaceFont(size: 11)
                            .foregroundColor(Color.mimo.textMuted)
                            .lineLimit(1)
                    }
                }
                if !command.isEnabled {
                    Text(L.t(AppLocalizationKey.locDisabled))
                        .interfaceFont(size: 10, weight: .medium)
                        .foregroundColor(Color.mimo.textMuted)
                }
            }
            Spacer()
            Button(command.isEnabled ? L.t(AppLocalizationKey.locDisable) : L.t(AppLocalizationKey.locEnable)) {
                CommandFileManager.setEnabled(command.name, enabled: !command.isEnabled)
                reload()
            }
            .interfaceFont(size: 11)
            .buttonStyle(HandCursorButtonStyle())
            .foregroundColor(command.isEnabled ? Color.mimo.textSecondary : Color.mimo.success)

            Button(action: {
                editor = CommandEditorModel(existing: command)
            }) {
                Image(systemName: "pencil").interfaceFont(size: 12).foregroundColor(Color.mimo.textSecondary)
            }
            .buttonStyle(HandCursorButtonStyle())
            .help(L.t(AppLocalizationKey.locEdit))

            Button(action: { commandToDelete = command }) {
                Image(systemName: "trash").interfaceFont(size: 12).foregroundColor(Color.mimo.error)
            }
            .buttonStyle(HandCursorButtonStyle())
            .help(L.t(AppLocalizationKey.locDelete))
        }
        .padding(12)
        .background(Color.mimo.surface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mimo.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func reload() {
        commands = CommandFileManager.load()
    }
}

/// Editor state for creating or editing a custom command.
struct CommandEditorModel: Identifiable {
    let id = UUID()
    var existingName: String?
    var name: String = ""
    var description: String = ""
    var template: String = ""
    let isEditing: Bool

    init() {
        isEditing = false
    }

    init(existing: CommandEntry) {
        isEditing = true
        existingName = existing.name
        name = existing.name
        let (nameValue, descriptionValue) = CommandFileManager.frontmatter(of: URL(fileURLWithPath: existing.path))
        description = descriptionValue ?? ""
        template = CommandFileManager.body(of: URL(fileURLWithPath: existing.path))
        _ = nameValue
    }
}

struct CommandEditorSheet: View {
    let model: CommandEditorModel
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var template = ""
    @State private var errorMessage: String?

    private var title: String {
        model.isEditing ? L.t(AppLocalizationKey.locEditCommand) : L.t(AppLocalizationKey.locAddCommand)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .interfaceFont(size: 18, weight: .bold)
                .foregroundColor(Color.mimo.textPrimary)

            VStack(alignment: .leading, spacing: 6) {
                Text(L.t(AppLocalizationKey.locCommandName))
                    .interfaceFont(size: 12, weight: .semibold)
                    .foregroundColor(Color.mimo.textSecondary)
                TextField("/name", text: $name)
                    .zcodeTextFieldStyle()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L.t(AppLocalizationKey.locDescriptionOptional))
                    .interfaceFont(size: 12, weight: .semibold)
                    .foregroundColor(Color.mimo.textSecondary)
                TextField(L.t(AppLocalizationKey.locDescriptionOptional), text: $description)
                    .zcodeTextFieldStyle()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L.t(AppLocalizationKey.locCommandTemplate))
                    .interfaceFont(size: 12, weight: .semibold)
                    .foregroundColor(Color.mimo.textSecondary)
                TextEditor(text: $template)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 180)
                    .padding(8)
                    .background(Color.mimo.surface)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mimo.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Text(L.t(AppLocalizationKey.locCommandPlaceholdersHint))
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textMuted)
            }

            if let errorMessage {
                Text(errorMessage)
                    .interfaceFont(size: 12)
                    .foregroundColor(Color.mimo.error)
            }

            HStack {
                Spacer()
                Button(L.t(AppLocalizationKey.locCancel)) { dismiss() }
                    .buttonStyle(.bordered)
                Button(L.t(AppLocalizationKey.locSave)) { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            name = model.name
            description = model.description
            template = model.template
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !CommandFileManager.sanitized(name: trimmedName).isEmpty else {
            errorMessage = L.t(AppLocalizationKey.locCommandBodyEmptyWarning)
            return
        }
        guard !template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = L.t(AppLocalizationKey.locCommandBodyEmptyWarning)
            return
        }
        do {
            if model.isEditing, let oldName = model.existingName {
                try CommandFileManager.update(from: oldName, name: trimmedName, description: description, template: template)
            } else {
                try CommandFileManager.create(name: trimmedName, description: description, template: template)
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
