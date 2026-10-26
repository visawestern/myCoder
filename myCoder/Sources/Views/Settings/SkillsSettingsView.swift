import SwiftUI

struct SkillsSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchQuery = ""
    @State private var skills: [SkillEntry] = []

    private var filtered: [SkillEntry] {
        AgentResourcesLoader.filterSkills(skills, query: searchQuery)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(L.t(AppLocalizationKey.locSkills))
                .interfaceFont(size: 24, weight: .bold)
                .foregroundColor(Color.mimo.textPrimary)

            Text(L.t(AppLocalizationKey.locBrowseTheLibraryAndInstallSkillsOneClickManageL))
                .interfaceFont(size: 14)
                .foregroundColor(Color.mimo.textSecondary)

            if !appState.supportsToolcallForSelection {
                Text(L.t(AppLocalizationKey.locToolsUnavailableForTheCurrentModelProvider))
                    .interfaceFont(size: 12)
                    .foregroundColor(Color.mimo.warning)
            }

            TextField(L.t(AppLocalizationKey.locSearchSkills), text: $searchQuery)
                .zcodeTextFieldStyle()

            AgentResourceLibraryView(
                mode: .skills,
                searchQuery: searchQuery,
                onInstalled: reloadSkills
            )

            Text(L.t(AppLocalizationKey.locInstalledCount).replacingOccurrences(of: "{0}", with: "\(filtered.count)"))
                .interfaceFont(size: 12, weight: .semibold)
                .foregroundColor(Color.mimo.textMuted)

            if filtered.isEmpty {
                settingsEmptyState(L.t(AppLocalizationKey.locNoSkillsInstalledYet), subtitle: L.t(AppLocalizationKey.locPickSkillFromTheLibraryAboveAndTapInstall))
            } else {
                ForEach(filtered) { skill in
                    InstalledSkillRow(skill: skill, record: record(for: skill.id), onChanged: reloadSkills)
                }
            }
        }
        .onAppear(perform: reloadSkills)
    }

    @State private var records: [InstalledSkillRecord] = []

    private func record(for id: String) -> InstalledSkillRecord? {
        records.first { $0.id == id }
    }

    private func reloadSkills() {
        skills = AgentResourcesLoader.loadSkills()
        records = SkillRegistryManager.load(homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
    }
}

/// Installed skill row with full admin: version/source badges, enable/disable
/// toggle, remove (plan Раздел 3 Блок 4 п.37).
struct InstalledSkillRow: View {
    let skill: SkillEntry
    let record: InstalledSkillRecord?
    let onChanged: () -> Void

    @State private var showRemoveConfirmation = false
    @State private var mutationError: String?

    private var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(skill.name)
                        .interfaceFont(size: 13, weight: .medium)
                        .foregroundColor(Color.mimo.textPrimary)
                    badge(skill.source)
                    if let v = record?.version { badge("v\(v)") }
                    if let r = record, !r.isEnabled { badge(L.t(AppLocalizationKey.locDisabled)) }
                }
                Text(skill.path)
                    .interfaceFont(size: 11, design: .monospaced)
                    .foregroundColor(Color.mimo.textMuted)
                    .lineLimit(1)
                if let mutationError {
                    Text(mutationError)
                        .interfaceFont(size: 10)
                        .foregroundColor(Color.mimo.error)
                        .lineLimit(2)
                }
            }
            Spacer()
            if let r = record {
                Button(r.isEnabled ? L.t(AppLocalizationKey.locDisable) : L.t(AppLocalizationKey.locEnable)) {
                    mutationError = nil
                    do {
                        guard try SkillRegistryManager.setEnabled(
                            id: skill.id,
                            enabled: !r.isEnabled,
                            homeDirectory: home
                        ) else {
                            mutationError = "The skill registry entry is missing."
                            return
                        }
                        onChanged()
                    } catch {
                        mutationError = error.localizedDescription
                    }
                }
                .interfaceFont(size: 11)
                .buttonStyle(HandCursorButtonStyle())
                .foregroundColor(r.isEnabled ? Color.mimo.textSecondary : Color.mimo.success)
            }
            Button(action: { showRemoveConfirmation = true }) {
                Image(systemName: "trash").interfaceFont(size: 12).foregroundColor(Color.mimo.error)
            }
            .buttonStyle(HandCursorButtonStyle())
            .help(L.t(AppLocalizationKey.locDelete))
        }
        .padding(12)
        .background(Color.mimo.surface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mimo.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .alert(L.t(AppLocalizationKey.locAlertRemoveSkill), isPresented: $showRemoveConfirmation) {
            Button(L.t(AppLocalizationKey.locCancel), role: .cancel) {}
            Button(L.t(AppLocalizationKey.locRemove), role: .destructive) { remove() }
        } message: {
            Text(L.t(AppLocalizationKey.locAlertDeleteSkillMessage)
                .replacingOccurrences(of: "{0}", with: skill.name)
                .replacingOccurrences(of: "{1}", with: MyCoderPaths.skillsDir(homeDirectory: home).path))
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .interfaceFont(size: 9, weight: .medium)
            .foregroundColor(Color.mimo.textMuted)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Color.mimo.backgroundAlt.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func remove() {
        mutationError = nil
        do {
            let dir = MyCoderPaths.skillDir(id: skill.id, homeDirectory: home)
            if FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.removeItem(at: dir)
            }
            guard try SkillRegistryManager.remove(id: skill.id, homeDirectory: home) else {
                mutationError = "The skill registry entry is missing."
                return
            }
            onChanged()
        } catch {
            mutationError = error.localizedDescription
        }
    }
}
