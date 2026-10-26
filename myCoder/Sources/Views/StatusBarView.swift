import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject var appState: AppState
    var isStreaming: Bool = false
    var isLoading: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle()
                    .fill(appState.selectedProviderConnected ? Color.mimo.success : Color.mimo.error)
                    .frame(width: 6, height: 6)
                Text(appState.selectedProviderConnected ? L.t(AppLocalizationKey.locConnected) : L.t(AppLocalizationKey.locDisconnected))
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textMuted)
            }
            
            Rectangle()
                .fill(Color.mimo.border)
                .frame(width: 1, height: 12)
            
            if let displayModel = StatusBarModelLogic.displayModel(
                selectedModel: appState.selectedModel,
                effectiveModel: appState.effectiveSelectedModel()
            ) {
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .interfaceFont(size: 10)
                    Text(displayModel)
                        .interfaceFont(size: 11, design: .monospaced)
                }
                .foregroundColor(Color.mimo.textSecondary)
            }
            
            Rectangle()
                .fill(Color.mimo.border)
                .frame(width: 1, height: 12)
            
            HStack(spacing: 4) {
                if isStreaming {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text(AppLocalization.string(.statusBarGenerating, language: appState.appLanguage))
                        .interfaceFont(size: 11)
                        .foregroundColor(Color.mimo.brand)
                } else if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text(AppLocalization.string(.statusBarProcessing, language: appState.appLanguage))
                        .interfaceFont(size: 11)
                        .foregroundColor(Color.mimo.textMuted)
                } else {
                    Text(AppLocalization.string(.statusBarIdle, language: appState.appLanguage))
                        .interfaceFont(size: 11)
                        .foregroundColor(Color.mimo.textMuted)
                }
            }
            
            Spacer()
            
            if appState.selectedProviderConnected {
                HStack(spacing: 4) {
                    Image(systemName: "network")
                        .interfaceFont(size: 10)
                    Text(ProviderConnectionStatusLogic.endpointLabel(
                        selectedID: appState.selectedProviderID,
                        serverProviderIDs: appState.serverProviders.map(\.id),
                        serverConnected: appState.serverConnected,
                        serverHost: appState.serverHost,
                        serverPort: appState.serverPort
                    ))
                        .interfaceFont(size: 11, design: .monospaced)
                }
                .foregroundColor(Color.mimo.textMuted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.mimo.surface)
        .overlay(
            Rectangle()
                .fill(Color.mimo.border)
                .frame(height: 1),
            alignment: .top
        )
    }
}
