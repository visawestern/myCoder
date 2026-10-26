import SwiftUI

enum AgentResourceLibraryMode {
    case skills
    case mcpServers
}

struct AgentResourceLibraryView: View {
    let mode: AgentResourceLibraryMode
    let searchQuery: String
    var onInstalled: () -> Void

    @State private var catalog: AgentResourceCatalogDocument?
    @State private var installingIDs: Set<String> = []
    @State private var installErrors: [String: String] = [:]
    @State private var installNotes: [String: String] = [:]
    @State private var loadError: String?
    @State private var installedRevision = 0
    @State private var uninstallCandidate: LibraryItem?

    private let installer = AgentResourceInstaller()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.t(AppLocalizationKey.locLibrary))
                .interfaceFont(size: 12, weight: .semibold)
                .foregroundColor(Color.mimo.textMuted)

            if let loadError {
                libraryMessage(loadError, tone: .warning)
            } else if catalog == nil {
                ProgressView()
                    .controlSize(.small)
            } else if visibleItems.isEmpty {
                libraryMessage("No library items match your search.", tone: .muted)
            } else {
                ForEach(visibleItems, id: \.id) { item in
                    libraryCard(item)
                }
            }
        }
        .onAppear(perform: loadCatalog)
        .alert(item: $uninstallCandidate) { item in
            Alert(
                title: Text(SkillUninstallPolicy.confirmationTitle(for: item.name)),
                message: Text(SkillUninstallPolicy.confirmationMessage(for: item.name)),
                primaryButton: .destructive(Text(L.t(AppLocalizationKey.locUninstall))) {
                    Task { await uninstall(item) }
                },
                secondaryButton: .cancel(Text(L.t(AppLocalizationKey.locCancel)))
            )
        }
    }

    private var visibleItems: [LibraryItem] {
        _ = installedRevision
        guard let catalog else { return [] }
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch mode {
        case .skills:
            return AgentResourceLibraryLogic.filterSkills(catalog.skills, query: searchQuery).map { skill in
                LibraryItem(
                    id: skill.id,
                    name: skill.name,
                    description: skill.description,
                    category: skill.category,
                    isInstalled: AgentResourceLibraryLogic.isSkillInstalled(id: skill.id, homeDirectory: home),
                    updateAvailable: SkillRegistryManager.updateAvailable(
                        for: skill.id,
                        catalogVersion: skill.version ?? "",
                        homeDirectory: home
                    ),
                    relatedHint: dependencyHint(
                        for: AgentDependencyResolver.resolve(skill: skill, homeDirectory: home),
                        mcpHint: skill.relatedMCPIDs.isEmpty
                            ? nil
                            : "MCP: \(skill.relatedMCPIDs.joined(separator: ", "))"
                    )
                )
            }
        case .mcpServers:
            return AgentResourceLibraryLogic.filterMCPServers(catalog.mcpServers, query: searchQuery).map { server in
                LibraryItem(
                    id: server.id,
                    name: server.name,
                    description: server.description,
                    category: server.category,
                    isInstalled: AgentResourceLibraryLogic.isMCPInstalled(id: server.id, homeDirectory: home),
                    updateAvailable: MCPRegistryManager.updateAvailable(
                        for: server.id,
                        catalogVersion: server.version ?? "",
                        homeDirectory: home
                    ),
                    relatedHint: dependencyHint(
                        for: AgentDependencyResolver.resolve(server: server, homeDirectory: home),
                        mcpHint: nil
                    )
                )
            }
        }
    }

    /// Human-readable dependency line (plan Section 4 п.17): "Requires node ≥18;
    /// playwright-mcp not installed" or nil when no declared dependencies exist.
    private func dependencyHint(for results: [AgentDependencyResolver.CheckResult], mcpHint: String?) -> String? {
        guard !results.isEmpty else { return mcpHint }
        let missing = results.filter { !$0.isSatisfied }
        let parts = results.map(\.detail)
        var line = "\(L.t(AppLocalizationKey.locRequires)): \(parts.joined(separator: "; "))"
        if let mcpHint = mcpHint {
            line += " · \(mcpHint)"
        }
        line += missing.isEmpty
            ? " · \(L.t(AppLocalizationKey.locDependenciesSatisfied))"
            : " · \(L.t(AppLocalizationKey.locDependenciesMissing))"
        return line
    }

    @ViewBuilder
    private func libraryCard(_ item: LibraryItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(item.name)
                        .interfaceFont(size: 13, weight: .semibold)
                        .foregroundColor(Color.mimo.textPrimary)
                    Text(item.category)
                        .interfaceFont(size: 10, weight: .medium)
                        .foregroundColor(Color.mimo.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.mimo.subtleFill)
                        .clipShape(Capsule())
                    if item.updateAvailable {
                        Text(L.t(AppLocalizationKey.locUpdateAvailable))
                            .interfaceFont(size: 10, weight: .semibold)
                            .foregroundColor(Color.mimo.warning)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.mimo.warning.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                Text(item.description)
                    .interfaceFont(size: 12)
                    .foregroundColor(Color.mimo.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let relatedHint = item.relatedHint {
                    Text(relatedHint)
                        .interfaceFont(size: 11)
                        .foregroundColor(Color.mimo.textMuted)
                }
                if let note = installNotes[item.id] {
                    Text("\(L.t(AppLocalizationKey.locNote)): \(note)")
                        .interfaceFont(size: 11)
                        .foregroundColor(Color.mimo.textMuted)
                }
                if let error = installErrors[item.id] {
                    Text(error)
                        .interfaceFont(size: 11)
                        .foregroundColor(Color.mimo.error)
                }
            }
            Spacer(minLength: 8)
            installButton(for: item)
        }
        .padding(12)
        .background(Color.mimo.surface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mimo.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func installButton(for item: LibraryItem) -> some View {
        if item.isInstalled {
            if installingIDs.contains(item.id) {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 72)
            } else if item.updateAvailable {
                Button(L.t(AppLocalizationKey.locUpdate)) {
                    Task { await update(item) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(Color.mimo.warning)
            } else {
                Button(L.t(AppLocalizationKey.locUninstall)) {
                    uninstallCandidate = item
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(Color.mimo.error)
            }
        } else if installingIDs.contains(item.id) {
            ProgressView()
                .controlSize(.small)
                .frame(width: 72)
        } else {
            Button(L.t(AppLocalizationKey.locInstall)) {
                Task { await install(item) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private func libraryMessage(_ text: String, tone: LibraryMessageTone) -> some View {
        Text(text)
            .interfaceFont(size: 12)
            .foregroundColor(tone.color)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.mimo.surface)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mimo.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func loadCatalog() {
        do {
            catalog = try AgentResourceCatalog.loadBundled()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    @MainActor
    private func install(_ item: LibraryItem) async {
        guard let catalog else { return }
        installingIDs.insert(item.id)
        installErrors[item.id] = nil
        installNotes[item.id] = nil
        defer { installingIDs.remove(item.id) }

        do {
            switch mode {
            case .skills:
                guard let skill = catalog.skills.first(where: { $0.id == item.id }) else { return }
                let unresolved = try await installer.installSkillWithDependencies(
                    skill,
                    catalog: catalog,
                    homeDirectory: FileManager.default.homeDirectoryForCurrentUser
                )
                if !unresolved.isEmpty {
                    installNotes[item.id] = unresolved.joined(separator: ", ")
                }
            case .mcpServers:
                guard let server = catalog.mcpServers.first(where: { $0.id == item.id }) else { return }
                try await installer.installMCPServer(server, homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
            }
            onInstalled()
            installedRevision += 1
        } catch {
            installErrors[item.id] = error.localizedDescription
        }
    }

    @MainActor
    private func update(_ item: LibraryItem) async {
        guard let catalog else { return }
        installingIDs.insert(item.id)
        installErrors[item.id] = nil
        defer { installingIDs.remove(item.id) }

        do {
            switch mode {
            case .skills:
                guard let skill = catalog.skills.first(where: { $0.id == item.id }) else { return }
                try installer.updateSkill(skill, homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
            case .mcpServers:
                guard let server = catalog.mcpServers.first(where: { $0.id == item.id }) else { return }
                try await installer.updateMCPServer(server, homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
            }
            onInstalled()
            installedRevision += 1
        } catch {
            installErrors[item.id] = error.localizedDescription
        }
    }

    @MainActor
    private func uninstall(_ item: LibraryItem) async {
        guard let catalog else { return }
        installingIDs.insert(item.id)
        installErrors[item.id] = nil
        defer { installingIDs.remove(item.id) }

        do {
            switch mode {
            case .skills:
                guard let skill = catalog.skills.first(where: { $0.id == item.id }) else { return }
                try installer.uninstallSkill(skill, homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
            case .mcpServers:
                guard let server = catalog.mcpServers.first(where: { $0.id == item.id }) else { return }
                try installer.uninstallMCPServer(server, homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
            }
            onInstalled()
            installedRevision += 1
        } catch {
            installErrors[item.id] = error.localizedDescription
        }
    }
}

private struct LibraryItem: Identifiable {
    let id: String
    let name: String
    let description: String
    let category: String
    let isInstalled: Bool
    let updateAvailable: Bool
    let relatedHint: String?
}

private enum LibraryMessageTone {
    case muted
    case warning

    var color: Color {
        switch self {
        case .muted: return Color.mimo.textMuted
        case .warning: return Color.mimo.warning
        }
    }
}
