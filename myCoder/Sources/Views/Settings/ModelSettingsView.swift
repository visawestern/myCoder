import AppKit
import SwiftUI

enum ModelSortOrder: String, CaseIterable, Identifiable {
    case name
    case context
    case reasoning
    case tools

    var id: String { rawValue }
    var title: String {
        switch self {
        case .name: return L.t(AppLocalizationKey.locSortName)
        case .context: return L.t(AppLocalizationKey.locSortContext)
        case .reasoning: return L.t(AppLocalizationKey.locSortReasoning)
        case .tools: return L.t(AppLocalizationKey.locSortTools)
        }
    }
}

struct ModelSettingsView: View {
    let availableWidth: CGFloat
    @EnvironmentObject var appState: AppState
    @State var showAddProvider = false
    @State var newProviderName = ""
    @State var newProviderType: ProviderType = .openAI
    @State var newProviderURL = ""
    @State var newProviderKey = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(L.t(AppLocalizationKey.locModelSettings))
                .interfaceFont(size: 24, weight: .bold)
                .foregroundColor(Color.mimo.textPrimary)
            
            Text(L.t(AppLocalizationKey.locConfigureModelProvidersAndManageAvailableModels))
                .interfaceFont(size: 14)
                .foregroundColor(Color.mimo.textSecondary)
            
            ModelSettingsProviderColumns(
                showAddProvider: $showAddProvider,
                availableWidth: availableWidth
            )
        }
        .sheet(isPresented: $showAddProvider) {
            AddProviderSheet(
                isPresented: $showAddProvider,
                name: $newProviderName,
                type: $newProviderType,
                url: $newProviderURL,
                apiKey: $newProviderKey
            )
            .environmentObject(appState)
        }
    }

}

struct ModelSettingsProviderColumns: View {
    @EnvironmentObject var appState: AppState
    @Binding var showAddProvider: Bool
    let availableWidth: CGFloat
    @State var detailProviderID: String = ""
    @State var customAPIKeyDraft: String = ""
    @State var customBaseURLDraft: String = ""
    @State var parameterModelID: String = ""
    @State var parameterProviderID: String = ""
    @State var parameterTemperature: String = ""
    @State var parameterMaxTokens: String = ""
    @State var parameterTopP: String = ""
    @State var parameterSystemPrompt: String = ""
    @State var parameterError: String?
    @State var modelSearchQuery: String = ""
    @State var modelSortOrder: ModelSortOrder = .name
    /// Collapsed model families in the provider model list.
    @State var collapsedModelFamilies: Set<String> = []
    @State var providerNameDraft: String = ""
    @State var localRefreshMessage: String?
    @State var providerPendingDelete: ProviderOption?
    @State var providerRevision: Int = 0
    @State var didRefreshProvider = false
    @State var localHostDraft: String = ""
    @State var localPortDraft: String = ""
    @State var editingModelProviderID: String = ""
    @State var cloneModelProviderID: String = ""
    @State var cloneSourceModelID: String = ""
    @State var cloneModelDraft: String = ""
    @State var newModelProviderID: String = ""
    @State var newModelDraft: String = ""
    @State var editingModelID: String = ""
    @State var editingModelDraft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L.t(AppLocalizationKey.locProvidersModels))
                    .interfaceFont(size: 16, weight: .semibold)
                    .foregroundColor(Color.mimo.textPrimary)
                Spacer()
                Button(action: { showAddProvider = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text(L.t(AppLocalizationKey.locAddProvider1))
                    }
                    .interfaceFont(size: 13)
                    .foregroundColor(Color.mimo.brand)
                }
                .buttonStyle(HandCursorButtonStyle())
                .help(L.t(AppLocalizationKey.locAddProvider1))
            }

            if layoutMode == .wide {
                HStack(alignment: .top, spacing: 12) {
                    providerListColumn
                        .frame(width: 200)
                    providerDetailColumn
                        .frame(width: 240)
                    modelsColumn
                        .frame(minWidth: 280, maxWidth: .infinity, alignment: .topLeading)
                        .layoutPriority(1)
                }
                // Custom-provider credentials and endpoint controls need more
                // room than the old 320pt card allowed; otherwise the Save /
                // Refresh actions were clipped and effectively unreachable.
                .frame(height: 480)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        providerListColumn
                            .frame(maxWidth: .infinity)
                        providerDetailColumn
                            .frame(maxWidth: .infinity)
                    }
                    .frame(height: 240)

                    modelsColumn
                        .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
                }
            }

        }
        .onAppear {
            if detailProviderID.isEmpty {
                // Prefill so Details/Models are populated instead of blank.
                detailProviderID = appState.selectedProviderID.isEmpty
                    ? (options.first?.id ?? "")
                    : appState.selectedProviderID
            }
        }
        .onChange(of: appState.selectedProviderID) { newValue in
            if !newValue.isEmpty {
                detailProviderID = newValue
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .providersChanged)) { _ in
            providerRevision &+= 1
            if !options.contains(where: { $0.id == detailProviderID }) {
                detailProviderID = options.first?.id ?? ""
            }
        }
        .alert(item: $providerPendingDelete) { option in
            Alert(
                title: Text(L.t(AppLocalizationKey.locRemoveProvider)),
                message: Text(option.name),
                primaryButton: .destructive(Text(L.t(AppLocalizationKey.locRemoveProvider))) {
                    removeProvider(option)
                },
                secondaryButton: .cancel()
            )
        }
    }


}
struct CustomProviderCard: View {
    let provider: CustomProvider
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        SettingsCard {
            HStack {
                Image(systemName: provider.type.icon)
                    .interfaceFont(size: 20)
                Text(provider.name)
                    .interfaceFont(size: 14, weight: .semibold)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Text(provider.type.rawValue)
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textMuted)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.mimo.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                
                Spacer()

                Toggle("", isOn: Binding(
                    get: { provider.isEnabled },
                    set: { appState.setProviderEnabled(provider.id, isEnabled: $0) }
                ))
                .labelsHidden()
                .toggleStyle(.dotSized)
                .frame(width: 22, height: 18)
                .contentShape(Rectangle())
                .help(provider.isEnabled ? L.t(AppLocalizationKey.locDisable) : L.t(AppLocalizationKey.locEnable))

                Button(action: {
                    appState.removeCustomProvider(provider)
                }) {
                    Image(systemName: "trash")
                        .interfaceFont(size: 12)
                        .foregroundColor(Color.mimo.error)
                }
                .buttonStyle(HandCursorButtonStyle())
                .help(L.t(AppLocalizationKey.locRemoveProvider))
            }
            
            Divider()
                .padding(.vertical, 8)
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L.t(AppLocalizationKey.locUrl))
                        .interfaceFont(size: 11)
                        .foregroundColor(Color.mimo.textMuted)
                    Text(provider.baseURL)
                        .interfaceFont(size: 11, design: .monospaced)
                        .foregroundColor(Color.mimo.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                
                if !provider.models.isEmpty {
                    HStack {
                        Text(L.t(AppLocalizationKey.locModels1))
                            .interfaceFont(size: 11)
                            .foregroundColor(Color.mimo.textMuted)
                        Text(L.t(AppLocalizationKey.locAvailableCount, provider.models.count))
                            .interfaceFont(size: 11)
                            .foregroundColor(Color.mimo.textSecondary)
                    }
                }
            }
        }
    }
}

struct AddProviderSheet: View {
    @Binding var isPresented: Bool
    @Binding var name: String
    @Binding var type: ProviderType
    @Binding var url: String
    @Binding var apiKey: String
    @EnvironmentObject var appState: AppState
    @State var isTesting = false
    @State var testResult: String?
    @State private var testSucceeded: Bool?
    @State var supportsTools = true
    @State var acpEnabled = false
    @State var requiresAPIKey = true
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L.t(AppLocalizationKey.locAddProvider))
                    .interfaceFont(size: 16, weight: .semibold)
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .interfaceFont(size: 16)
                        .foregroundColor(Color.mimo.textMuted)
                }
                .buttonStyle(HandCursorButtonStyle())
                .help(L.t(AppLocalizationKey.locClose))
            }
            .padding(16)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L.t(AppLocalizationKey.locProviderType))
                            .interfaceFont(size: 13, weight: .medium)
                            .foregroundColor(Color.mimo.textPrimary)
                        
                        Picker(L.t(AppLocalizationKey.locProviderType), selection: $type) {
                            ForEach(ProviderType.allCases) { t in
                                Label(t.rawValue, systemImage: t.icon).tag(t)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onChange(of: type) { newType in
                            url = newType.defaultURL
                            requiresAPIKey = ProviderEndpointLogic.defaultRequiresAPIKey(for: newType)
                            if newType == .openCodeZen,
                               name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                name = L.t(AppLocalizationKey.locOpenCodeZen)
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L.t(AppLocalizationKey.locName))
                            .interfaceFont(size: 13, weight: .medium)
                            .foregroundColor(Color.mimo.textPrimary)
                        TextField(L.t(AppLocalizationKey.locProviderNameExample), text: $name)
                            .zcodeTextFieldStyle()
                        Text(L.t(AppLocalizationKey.locProviderNameOptional))
                            .interfaceFont(size: 10)
                            .foregroundColor(Color.mimo.textMuted)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L.t(AppLocalizationKey.locBaseUrl))
                            .interfaceFont(size: 13, weight: .medium)
                            .foregroundColor(Color.mimo.textPrimary)
                        TextField(L.t(AppLocalizationKey.locApiEndpointURL), text: $url)
                            .zcodeTextFieldStyle()
                            .interfaceFont(size: 12, design: .monospaced)
                        if !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           ProviderEndpointLogic.normalizedBaseURL(url) == nil {
                            Text(L.t(AppLocalizationKey.locInvalidEndpoint))
                                .interfaceFont(size: 10)
                                .foregroundColor(Color.mimo.error)
                        }
                    }
                    
                    if type != .ollama && type != .acp && (requiresAPIKey || type == .openCodeZen) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(type == .openCodeZen ? L.t(AppLocalizationKey.locOpenCodeZenApiKeyOptional) : L.t(AppLocalizationKey.locApiKey))
                                .interfaceFont(size: 13, weight: .medium)
                                .foregroundColor(Color.mimo.textPrimary)
                            SecureField(type == .openModel ? "om-..." : L.t(AppLocalizationKey.locSecretKeyPlaceholder), text: $apiKey)
                                .zcodeTextFieldStyle()
                            if type == .openCodeZen {
                                Text(L.t(AppLocalizationKey.locNoZenKeyDescription))
                                    .interfaceFont(size: 11)
                                    .foregroundColor(Color.mimo.textSecondary)
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(type == .openCodeZen ? "Require a Zen API key" : L.t(AppLocalizationKey.locRequiresAPIKey), isOn: $requiresAPIKey)
                            .interfaceFont(size: 13, weight: .medium)
                        Text(L.t(AppLocalizationKey.locDisableForLocalModelsProvidersThatDontNeedAuthe))
                            .interfaceFont(size: 11)
                            .foregroundColor(Color.mimo.textSecondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(L.t(AppLocalizationKey.locEnableToolCalling), isOn: $supportsTools)
                            .interfaceFont(size: 13, weight: .medium)
                        Text(L.t(AppLocalizationKey.locEnableFunctiontoolCallingSupportForThisProvider))
                            .interfaceFont(size: 11)
                            .foregroundColor(Color.mimo.textSecondary)
                    }
                    
                    if type == .acp {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(L.t(AppLocalizationKey.locEnableACP), isOn: $acpEnabled)
                                .interfaceFont(size: 13, weight: .medium)
                            Text(L.t(AppLocalizationKey.locEnableAgentCoderProtocolForAutonomousCodingTask))
                                .interfaceFont(size: 11)
                                .foregroundColor(Color.mimo.textSecondary)
                        }
                    }
                    
                    if let result = testResult, let succeeded = testSucceeded {
                        ProviderConnectionResultBanner(message: result, succeeded: succeeded)
                    }
                }
                .padding(16)
            }
            
            Divider()
            
            HStack {
                Button(action: {
                    isTesting = true
                    Task {
                        let success = await appState.testProvider(
                            url: ProviderEndpointLogic.normalizedBaseURL(url) ?? url,
                            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                            type: type
                        )
                        await MainActor.run {
                            isTesting = false
                            testSucceeded = success
                            testResult = success ? L.t(AppLocalizationKey.locConnectionSuccess) : L.t(AppLocalizationKey.locConnectionFailed)
                        }
                    }
                }) {
                    if isTesting {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Text(L.t(AppLocalizationKey.locTestConnection))
                    }
                }
                .buttonStyle(.bordered)
                .disabled(ProviderEndpointLogic.normalizedBaseURL(url) == nil)
                .help(L.t(AppLocalizationKey.locTestConnection))
                
                Spacer()
                
                Button(L.t(AppLocalizationKey.locCancel)) {
                    isPresented = false
                }
                .buttonStyle(HandCursorButtonStyle())
                .foregroundColor(Color.mimo.textSecondary)
                .help(L.t(AppLocalizationKey.locCancel))
                
                Button(action: {
                    guard let normalizedURL = ProviderEndpointLogic.normalizedBaseURL(url) else { return }
                    let resolvedName = ProviderNameLogic.resolvedName(
                        name,
                        fallback: type.rawValue,
                        existing: appState.manageableProviderOptions.map(\.name)
                    )
                    let provider = CustomProvider(
                        id: UUID().uuidString,
                        name: resolvedName,
                        type: type,
                        baseURL: normalizedURL,
                        apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                        isEnabled: true,
                        models: [],
                        supportsTools: supportsTools,
                        acpEnabled: acpEnabled,
                        requiresAPIKey: requiresAPIKey
                    )
                    appState.addCustomProvider(provider)
                    isPresented = false
                    name = ""
                    url = ""
                    apiKey = ""
                    requiresAPIKey = true
                }) {
                    Text(L.t(AppLocalizationKey.locAddProvider))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(ProviderEndpointLogic.normalizedBaseURL(url) == nil
                             ? Color.mimo.textMuted : Color.mimo.brand)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(HandCursorButtonStyle())
                .disabled(ProviderEndpointLogic.normalizedBaseURL(url) == nil)
                .help(L.t(AppLocalizationKey.locAddProvider1))
            }
            .padding(16)
        }
        .frame(width: 480, height: 600)
        .background(Color.mimo.background)
    }
}


private struct ProviderConnectionResultBanner: View {
    let message: String
    let succeeded: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .interfaceFont(size: 17, weight: .semibold)
                .foregroundColor(succeeded ? Color.mimo.success : Color.mimo.error)
            VStack(alignment: .leading, spacing: 2) {
                Text(succeeded ? "Connection verified" : "Connection failed")
                    .interfaceFont(size: 12, weight: .semibold)
                    .foregroundColor(Color.mimo.textPrimary)
                Text(message)
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background((succeeded ? Color.mimo.success : Color.mimo.error).opacity(0.13))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke((succeeded ? Color.mimo.success : Color.mimo.error).opacity(0.55), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}
