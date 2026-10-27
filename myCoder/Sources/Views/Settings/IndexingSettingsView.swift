import SwiftUI

struct IndexingSettingsView: View {
    @EnvironmentObject var appState: AppState
    
    private var indexNewFoldersBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.indexNewFolders },
            set: { newValue in appState.updateSettings { $0.indexNewFolders = newValue } }
        )
    }
    
    private var indexRepositoriesBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.indexRepositories },
            set: { newValue in appState.updateSettings { $0.indexRepositories = newValue } }
        )
    }

    /// Point context is a per-user switch, not a workspace setting: it changes
    /// what every send attaches, regardless of which project is open.
    private var pointContextBinding: Binding<Bool> {
        Binding(
            get: { appState.isPointContextEnabled },
            set: { newValue in appState.isPointContextEnabled = newValue }
        )
    }

    /// The local planner only makes sense with point context: without a
    /// compiled pack there is nothing to plan.
    private var localPlannerBinding: Binding<Bool> {
        Binding(
            get: { appState.isLocalQueryPlannerEnabled },
            set: { newValue in appState.isLocalQueryPlannerEnabled = newValue }
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(L.t(AppLocalizationKey.locIndexing))
                .interfaceFont(size: 24, weight: .bold)
                .foregroundColor(Color.mimo.textPrimary)
            
            Text(L.t(AppLocalizationKey.locCodebase))
                .interfaceFont(size: 14, weight: .semibold)
                .foregroundColor(Color.mimo.textMuted)

            Text(IndexingSettingsLogic.statusMessage)
                .interfaceFont(size: 12)
                .foregroundColor(Color.mimo.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            SettingsCard {
                SettingsToggleRow(title: L.t(AppLocalizationKey.locIndexNewFolders), description: L.t(AppLocalizationKey.locAutomaticallyIndexAnyNewFoldersWithFewerThan500), isOn: indexNewFoldersBinding)
                    .disabled(!IndexingSettingsLogic.automaticIndexingIsAvailable)

                SettingsToggleRow(title: L.t(AppLocalizationKey.locIndexRepositoriesForInstantGrepBeta), description: L.t(AppLocalizationKey.locAutomaticallyIndexRepositoriesSpeedGrepSearches), isOn: indexRepositoriesBinding)
                    .disabled(!IndexingSettingsLogic.automaticIndexingIsAvailable)

                SettingsToggleRow(title: L.t(AppLocalizationKey.locPointContext), description: L.t(AppLocalizationKey.locPointContextDescription), isOn: pointContextBinding)

                SettingsToggleRow(title: L.t(AppLocalizationKey.locLocalQueryPlanner), description: L.t(AppLocalizationKey.locLocalQueryPlannerDescription), isOn: localPlannerBinding)
                    .disabled(!appState.isPointContextEnabled)
            }
        }
    }
}
