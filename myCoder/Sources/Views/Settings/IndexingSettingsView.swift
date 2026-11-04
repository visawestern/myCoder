import SwiftUI

struct IndexingSettingsView: View {
    @EnvironmentObject var appState: AppState
    /// B3: the banner must disappear the moment a model is assigned, so the
    /// store is observed, not read once.
    @ObservedObject private var internalModelStore = InternalModelStore.shared

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

                // B3: a planner without an assigned internal model silently
                // degrades to the deterministic plan — the banner says it out
                // loud and jumps to the provider list in one click.
                if appState.isLocalQueryPlannerEnabled && internalModelStore.models.isEmpty {
                    internalModelBanner
                }
            }
        }
    }

    private var internalModelBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Color.mimo.warning)
                .font(.system(size: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(L.t(AppLocalizationKey.locPlannerNoInternalModelTitle))
                    .interfaceFont(size: 12, weight: .semibold)
                    .foregroundColor(Color.mimo.textPrimary)
                Text(L.t(AppLocalizationKey.locPlannerNoInternalModelBody))
                    .interfaceFont(size: 10)
                    .foregroundColor(Color.mimo.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button {
                appState.showSettings = true
                appState.settingsTab = .providers
            } label: {
                Text(L.t(AppLocalizationKey.locAddInternalModel))
                    .interfaceFont(size: 11, weight: .medium)
                    .foregroundColor(Color.mimo.brand)
            }
            .buttonStyle(HandCursorButtonStyle())
            .help(L.t(AppLocalizationKey.locAddInternalModel))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.mimo.warning.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mimo.warning.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
