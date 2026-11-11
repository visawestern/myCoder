import SwiftUI

/// Settings tab for local Language Servers (LSP).
///
/// User directive 2026-11-08: give the agent local language servers to choose
/// from. This screen shows which standard servers are actually installed on
/// this machine (discovered on PATH), lets the user enable/disable them, and
/// allows adding a custom server. State lives in `~/.mycoder/lsp.json` and
/// the LSP registry (`~/.mycoder/lsp/registry.json`).
struct LSPServersSettingsView: View {
    @State private var rows: [LSPServerRow] = []
    @State private var customID = ""
    @State private var customCommand = ""
    @State private var customLanguages = ""

    private var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    private var configURL: URL { MyCoderPaths.lspConfigURL(homeDirectory: home) }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(L.t("Language Servers (LSP)"))
                .interfaceFont(size: 24, weight: .bold)
                .foregroundColor(Color.mimo.textPrimary)

            Text(L.t("Local language servers the agent can choose from. Only servers whose binary is found on PATH are shown."))
                .interfaceFont(size: 14)
                .foregroundColor(Color.mimo.textSecondary)

            // Custom server form.
            SettingsCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L.t("Add a custom server")).interfaceFont(size: 13, weight: .semibold)
                    HStack(spacing: 8) {
                        TextField(L.t("id (e.g. my-lsp)"), text: $customID)
                            .zcodeTextFieldStyle()
                            .frame(maxWidth: 160)
                        TextField(L.t("command"), text: $customCommand)
                            .zcodeTextFieldStyle()
                        TextField(L.t("languages (comma-separated)"), text: $customLanguages)
                            .zcodeTextFieldStyle()
                            .frame(maxWidth: 200)
                        Button(L.t(AppLocalizationKey.locAdd)) { addCustom() }
                            .buttonStyle(HandCursorButtonStyle())
                            .disabled(customID.trimmingCharacters(in: .whitespaces).isEmpty || customCommand.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }

            Text(L.t("Found %d of %d", rows.filter { !$0.isCustom }.count, rows.count))
                .interfaceFont(size: 12, weight: .semibold)
                .foregroundColor(Color.mimo.textMuted)

            if rows.isEmpty {
                settingsEmptyState(L.t("No language servers found"), subtitle: L.t("Install one of the standard servers (sourcekit-lsp, typescript-language-server, pyright, etc.) or add your own."))
            } else {
                ForEach($rows) { $row in
                    LSPServerRowView(row: $row, onChanged: reload)
                }
            }
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        let specs = LSPDiscovery.available()
        let specByID = Dictionary(uniqueKeysWithValues: specs.map { ($0.id, $0) })
        let registry = LSPRegistryManager.load(homeDirectory: home)
        let enabledByID = Dictionary(uniqueKeysWithValues: registry.map { ($0.id, $0.isEnabled) })

        // Custom servers from lsp.json that are not in the standard catalog.
        var customIDs: Set<String> = []
        var customMap: [String: LSPServerSpec] = [:]
        if let data = try? Data(contentsOf: configURL),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let servers = root["lspServers"] as? [String: Any] {
            for (id, value) in servers {
                guard specByID[id] == nil, let entry = value as? [String: Any] else { continue }
                let command = entry["command"] as? String ?? ""
                let args = entry["args"] as? [String] ?? []
                let languages = entry["languages"] as? [String] ?? []
                customMap[id] = LSPServerSpec(id: id, name: id, command: command, args: args, languages: languages)
                customIDs.insert(id)
            }
        }

        var result: [LSPServerRow] = []
        for spec in specs {
            result.append(LSPServerRow(
                id: spec.id, name: spec.name, command: spec.command,
                args: spec.args, languages: spec.languages,
                isEnabled: enabledByID[spec.id] ?? true, isCustom: false
            ))
        }
        for id in customIDs.sorted() {
            if let spec = customMap[id] {
                result.append(LSPServerRow(
                    id: spec.id, name: spec.name, command: spec.command,
                    args: spec.args, languages: spec.languages,
                    isEnabled: enabledByID[spec.id] ?? true, isCustom: true
                ))
            }
        }
        rows = result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func addCustom() {
        let id = customID.trimmingCharacters(in: .whitespaces)
        let command = customCommand.trimmingCharacters(in: .whitespaces)
        let languages = customLanguages
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var data = (try? Data(contentsOf: configURL)) ?? Data()
        do {
            data = try LSPConfigMutationLogic.upsertServer(
                data: data, id: id, command: command, args: [], languages: languages)
            try data.write(to: configURL, options: .atomic)
            _ = try LSPRegistryManager.upsert(InstalledLSPRecord(
                id: id, version: "1.0.0", installedAt: Date(),
                source: .cursor, isEnabled: true, command: command, args: [], languages: languages
            ), homeDirectory: home)
            customID = ""; customCommand = ""; customLanguages = ""
            reload()
        } catch {
            // keep fields, nothing persisted
        }
    }
}

struct LSPServerRow: Identifiable, Equatable {
    let id: String
    let name: String
    let command: String
    let args: [String]
    let languages: [String]
    var isEnabled: Bool
    let isCustom: Bool
}

struct LSPServerRowView: View {
    @Binding var row: LSPServerRow
    let onChanged: () -> Void

    @State private var mutationError: String?

    private var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    private var configURL: URL { MyCoderPaths.lspConfigURL(homeDirectory: home) }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(row.isEnabled ? Color.mimo.success : Color.mimo.textMuted)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(row.name).interfaceFont(size: 13, weight: .medium)
                        .foregroundColor(Color.mimo.textPrimary)
                    if row.isCustom {
                        Text(L.t("custom")).interfaceFont(size: 10)
                            .foregroundColor(Color.mimo.textMuted)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.mimo.backgroundAlt)
                            .clipShape(Capsule())
                    }
                }
                Text("\(row.command) \(row.args.joined(separator: " "))")
                    .interfaceFont(size: 11, design: .monospaced)
                    .foregroundColor(Color.mimo.textMuted)
                    .lineLimit(1)
                if !row.languages.isEmpty {
                    Text(row.languages.joined(separator: ", "))
                        .interfaceFont(size: 11)
                        .foregroundColor(Color.mimo.textMuted)
                }
                if let mutationError {
                    Text(mutationError).interfaceFont(size: 10).foregroundColor(Color.mimo.error)
                }
            }
            Spacer()
            Button(row.isEnabled ? L.t(AppLocalizationKey.locDisable) : L.t(AppLocalizationKey.locEnable)) {
                toggle()
            }
            .interfaceFont(size: 11)
            .buttonStyle(HandCursorButtonStyle())
            .foregroundColor(row.isEnabled ? Color.mimo.textSecondary : Color.mimo.success)

            if row.isCustom {
                Button(action: { remove() }) {
                    Image(systemName: "trash").interfaceFont(size: 12).foregroundColor(Color.mimo.error)
                }
                .buttonStyle(HandCursorButtonStyle())
                .help(L.t(AppLocalizationKey.locDelete))
            }
        }
        .padding(12)
        .background(Color.mimo.surface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mimo.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func ensureEntry() throws {
        var data = (try? Data(contentsOf: configURL)) ?? Data()
        data = try LSPConfigMutationLogic.upsertServer(
            data: data, id: row.id, command: row.command, args: row.args, languages: row.languages)
        try data.write(to: configURL, options: .atomic)
    }

    private func toggle() {
        mutationError = nil
        let newEnabled = !row.isEnabled
        do {
            try ensureEntry()
            var data = try Data(contentsOf: configURL)
            data = try LSPConfigMutationLogic.setDisabled(data: data, id: row.id, disabled: !newEnabled)
            let original = try Data(contentsOf: configURL)
            do {
                try data.write(to: configURL, options: .atomic)
                guard try LSPRegistryManager.setEnabled(id: row.id, enabled: newEnabled, homeDirectory: home) else {
                    throw LSPConfigMutationError.targetMissing(row.id)
                }
            } catch {
                try? original.write(to: configURL, options: .atomic)
                throw error
            }
            row.isEnabled = newEnabled
            onChanged()
        } catch {
            mutationError = L.t("Could not change state: %@", error.localizedDescription)
        }
    }

    private func remove() {
        mutationError = nil
        do {
            var data = try Data(contentsOf: configURL)
            data = try LSPConfigMutationLogic.remove(data: data, id: row.id)
            try data.write(to: configURL, options: .atomic)
            _ = try LSPRegistryManager.remove(id: row.id, homeDirectory: home)
            onChanged()
        } catch {
            mutationError = L.t("Could not delete: %@", error.localizedDescription)
        }
    }
}
