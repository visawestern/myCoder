import SwiftUI

struct PluginsSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchQuery = ""
    @State private var plugins: [PluginEntry] = []

    private var filtered: [PluginEntry] {
        AgentResourcesLoader.filterEntries(plugins, query: searchQuery) { $0.name }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(L.t(AppLocalizationKey.locPlugins))
                .interfaceFont(size: 24, weight: .bold)
                .foregroundColor(Color.mimo.textPrimary)

            Text(L.t(AppLocalizationKey.locEnableDisableInstalledPluginsPluginsBundleSkill))
                .interfaceFont(size: 14)
                .foregroundColor(Color.mimo.textSecondary)

            if !appState.supportsToolcallForSelection {
                Text(L.t(AppLocalizationKey.locToolsUnavailableForTheCurrentModelProvider))
                    .interfaceFont(size: 12)
                    .foregroundColor(Color.mimo.warning)
            }

            TextField(L.t(AppLocalizationKey.locSearchPlugins), text: $searchQuery)
                .zcodeTextFieldStyle()

            if filtered.isEmpty {
                settingsEmptyState(L.t(AppLocalizationKey.locNoPluginsInstalled), subtitle: L.t(AppLocalizationKey.locPluginsLiveUnderMycoderplugins))
            } else {
                ForEach(filtered) { plugin in
                    HStack {
                        Text(plugin.name)
                            .interfaceFont(size: 13, weight: .medium)
                            .foregroundColor(Color.mimo.textPrimary)
                        Spacer()
                        Button(plugin.isEnabled ? L.t(AppLocalizationKey.locDisable) : L.t(AppLocalizationKey.locEnable)) {
                            PluginEntry.togglePlugin(id: plugin.id)
                            plugins = AgentResourcesLoader.loadPlugins()
                        }
                        .interfaceFont(size: 11)
                        .buttonStyle(HandCursorButtonStyle())
                        .foregroundColor(plugin.isEnabled ? Color.mimo.textSecondary : Color.mimo.success)
                        .help(plugin.isEnabled ? "Disable plugin" : "Enable plugin")
                    }
                    .padding(12)
                    .background(Color.mimo.surface)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mimo.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .onAppear {
            plugins = AgentResourcesLoader.loadPlugins()
        }
    }
}
