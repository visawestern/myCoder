import SwiftUI

/// Session-scoped health check cache + concurrency limiter.
/// Prevents N parallel probes on every tab appear and caches results per session.
@MainActor
final class MCPHealthSession {
    static let shared = MCPHealthSession()
    private var cache: [String: MCPHealthStatus] = [:]
    private var inFlight: Set<String> = []
    private let maxConcurrent = 3
    private var running = 0

    func cachedStatus(for id: String) -> MCPHealthStatus? { cache[id] }

    func isChecking(_ id: String) -> Bool { inFlight.contains(id) }

    func update(_ id: String, _ status: MCPHealthStatus) {
        cache[id] = status
        inFlight.remove(id)
        running = max(0, running - 1)
    }

    func beginCheck(_ id: String) -> Bool {
        guard !inFlight.contains(id), running < maxConcurrent else { return false }
        inFlight.insert(id)
        running += 1
        return true
    }
}

struct MCPServersSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchQuery = ""
    @State private var servers: [MCPServerEntry] = []

    private var filtered: [MCPServerEntry] {
        AgentResourcesLoader.filterEntries(servers, query: searchQuery) { $0.name }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(L.t(AppLocalizationKey.locMcpServers))
                .interfaceFont(size: 24, weight: .bold)
                .foregroundColor(Color.mimo.textPrimary)

            Text(L.t(AppLocalizationKey.locBrowseTheLibraryAndInstallMcpServersOneClickCon))
                .interfaceFont(size: 14)
                .foregroundColor(Color.mimo.textSecondary)

            if !appState.supportsToolcallForSelection {
                Text(L.t(AppLocalizationKey.locToolsUnavailableForTheCurrentModelProvider))
                    .interfaceFont(size: 12)
                    .foregroundColor(Color.mimo.warning)
            }

            TextField(L.t(AppLocalizationKey.locSearchMCPServers), text: $searchQuery)
                .zcodeTextFieldStyle()

            AgentResourceLibraryView(
                mode: .mcpServers,
                searchQuery: searchQuery,
                onInstalled: reloadServers
            )

            Text("\(L.t(AppLocalizationKey.locConfigured)) \(filtered.count)")
                .interfaceFont(size: 12, weight: .semibold)
                .foregroundColor(Color.mimo.textMuted)

            if filtered.isEmpty {
                settingsEmptyState(L.t(AppLocalizationKey.locNoMCPServersConfigured), subtitle: L.t(AppLocalizationKey.locPickServerFromTheLibraryAboveAndTapInstall))
            } else {
                ForEach(filtered) { server in
                    InstalledMCPRow(server: server, onChanged: reloadServers)
                }
            }
        }
        .onAppear(perform: reloadServers)
    }

    private func reloadServers() {
        servers = AgentResourcesLoader.loadMCPServers()
    }
}

/// Installed MCP row with full admin: health dot, enable/disable (writes the
/// `disabled` flag to mcp.json), remove (plan Раздел 4 Блок 4 п.37). The dot
/// reflects the *real* health probe (E11): green = alive, red = failing,
/// gray = disabled / not yet checked — never the enabled preference alone.
struct InstalledMCPRow: View {
    let server: MCPServerEntry
    let onChanged: () -> Void

    @State private var showRemoveConfirmation = false
    @State private var healthStatus: MCPHealthStatus = .unknown
    @State private var mutationError: String?

    private var configURL: URL {
        MyCoderPaths.mcpConfigURL(homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
    }
    private var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    private var healthColor: Color {
        switch healthStatus {
        case .healthy: return Color.mimo.success
        case .unhealthy: return Color.mimo.error
        case .unknown: return Color.mimo.textMuted
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(healthColor)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 4) {
                Text(server.name)
                    .interfaceFont(size: 13, weight: .medium)
                    .foregroundColor(Color.mimo.textPrimary)
                if let command = server.command {
                    Text(command)
                        .interfaceFont(size: 11, design: .monospaced)
                        .foregroundColor(Color.mimo.textMuted)
                        .lineLimit(1)
                }
                if let mutationError {
                    Text(mutationError)
                        .interfaceFont(size: 10)
                        .foregroundColor(Color.mimo.error)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button(server.isEnabled ? L.t(AppLocalizationKey.locDisable) : L.t(AppLocalizationKey.locEnable)) {
                setDisabled(!server.isEnabled)
            }
            .interfaceFont(size: 11)
            .buttonStyle(HandCursorButtonStyle())
            .foregroundColor(server.isEnabled ? Color.mimo.textSecondary : Color.mimo.success)

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
        .alert(L.t(AppLocalizationKey.locAlertRemoveMCPServer), isPresented: $showRemoveConfirmation) {
            Button(L.t(AppLocalizationKey.locCancel), role: .cancel) {}
            Button(L.t(AppLocalizationKey.locRemove), role: .destructive) { remove() }
        } message: {
            Text(L.t(AppLocalizationKey.locAlertDeleteMCPMessage).replacingOccurrences(of: "{0}", with: server.name).replacingOccurrences(of: "{1}", with: configURL.path))
        }
        .task(id: server.id) {
            await refreshHealth()
        }
    }

    /// Runs a real health probe (HTTP GET or stdio PATH resolution) with
    /// session caching and concurrency limiting. Skips if already cached this
    /// session or if max concurrent checks are running.
    private func refreshHealth() async {
        let session = MCPHealthSession.shared

        // 1) Use session cache to avoid re-probe on tab switch.
        if let cached = session.cachedStatus(for: server.id) {
            healthStatus = cached
            return
        }

        // 2) Fall back to registry if recent (<5 min).
        let registryStatus = MCPRegistryManager.load(homeDirectory: home)
            .first(where: { $0.id == server.id })
        let mapped = MCPHealthCheckLogic.status(
            isEnabled: server.isEnabled,
            lastCheck: registryStatus?.lastHealthCheck,
            lastStatus: registryStatus?.lastHealthStatus
        )
        if mapped != .unknown {
            healthStatus = mapped
            session.update(server.id, mapped)
            return
        }

        // 3) Throttle concurrent probes (max 3).
        guard session.beginCheck(server.id) else {
            healthStatus = .unknown
            return
        }

        let checker = MCPHealthChecker()
        if let fresh = try? await checker.check(server, homeDirectory: home) {
            let status: MCPHealthStatus = fresh ? .healthy : .unhealthy
            healthStatus = status
            session.update(server.id, status)
            return
        }
        healthStatus = .unknown
        _ = session.beginCheck(server.id); session.update(server.id, .unknown)
    }

    private func setDisabled(_ disabled: Bool) {
        mutationError = nil
        do {
            let data = try Data(contentsOf: configURL)
            let output = try MCPConfigMutationLogic.setDisabled(data: data, id: server.id, disabled: disabled)
            let originalData = data
            do {
                try output.write(to: configURL, options: .atomic)
                guard try MCPRegistryManager.setEnabled(id: server.id, enabled: !disabled, homeDirectory: home) else {
                    throw MCPConfigMutationError.targetMissing(server.id)
                }
            } catch {
                try? originalData.write(to: configURL, options: .atomic)
                throw error
            }
            onChanged()
        } catch {
            mutationError = error.localizedDescription
        }
    }

    private func remove() {
        mutationError = nil
        do {
            let data = try Data(contentsOf: configURL)
            let output = try MCPConfigMutationLogic.remove(data: data, id: server.id)
            let originalData = data
            do {
                try output.write(to: configURL, options: .atomic)
                guard try MCPRegistryManager.remove(id: server.id, homeDirectory: home) else {
                    throw MCPConfigMutationError.targetMissing(server.id)
                }
            } catch {
                try? originalData.write(to: configURL, options: .atomic)
                throw error
            }
            onChanged()
        } catch {
            mutationError = error.localizedDescription
        }
    }
}
