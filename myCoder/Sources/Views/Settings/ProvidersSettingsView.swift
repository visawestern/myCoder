import SwiftUI

struct UnifiedProvidersView: View {
    @EnvironmentObject var appState: AppState
    let availableWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            InternalModelsSection()
            Divider().background(Color.mimo.border)
            ModelSettingsView(availableWidth: availableWidth)
            Divider().background(Color.mimo.border)
            LocalProvidersSection()
            Divider().background(Color.mimo.border)
            WebProvidersSection()
        }
    }
}


struct ProvidersSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showAddProvider = false
    @State private var providerFilter = ""
    @State private var newProviderName = ""
    @State private var newProviderType: ProviderType = .openAI
    @State private var newProviderURL = ""
    @State private var newProviderKey = ""
    
    private var filteredProviders: [ProviderOption] {
        if providerFilter.isEmpty {
            return appState.providerOptions
        }
        return appState.providerOptions.filter {
            $0.name.localizedCaseInsensitiveContains(providerFilter)
        }
    }
    
    private var providerCount: Int {
        appState.providerOptions.count
    }
    
    private var modelCount: Int {
        appState.availableModels.count
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(L.t(AppLocalizationKey.locProviders))
                .interfaceFont(size: 24, weight: .bold)
                .foregroundColor(Color.mimo.textPrimary)
            
            Text(L.t(AppLocalizationKey.locManageCustomModelProvidersAndViewServerconnecte))
                .interfaceFont(size: 14)
                .foregroundColor(Color.mimo.textSecondary)
            
            // Stats chips
            HStack(spacing: 16) {
                ProviderCountChip(title: L.t(AppLocalizationKey.locProviders), count: providerCount)
                ProviderCountChip(title: L.t(AppLocalizationKey.locModels), count: modelCount)
                Spacer()
            }
            
            // Search and add
            searchAndAddSection
            
            // Providers list
            providersList
            
            // Add provider sheet
            if showAddProvider {
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
    
    private var searchAndAddSection: some View {
        HStack {
            TextField(L.t(AppLocalizationKey.locSearchProviders), text: $providerFilter)
                .zcodeTextFieldStyle()
                .interfaceFont(size: 13)
            
            Button(action: { showAddProvider = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text(L.t(AppLocalizationKey.locAdd))
                }
                .interfaceFont(size: 13)
                .foregroundColor(Color.mimo.brand)
            }
            .buttonStyle(HandCursorButtonStyle())
            .help(L.t(AppLocalizationKey.locAddProvider1))
        }
    }
    
    private var providersList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.t(AppLocalizationKey.locProviders))
                .interfaceFont(size: 16, weight: .semibold)
                .foregroundColor(Color.mimo.textPrimary)
            
            if filteredProviders.isEmpty {
                Text(L.t(AppLocalizationKey.locProvidersConfigured))
                    .interfaceFont(size: 13)
                    .foregroundColor(Color.mimo.textMuted)
                    .padding(16)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(filteredProviders) { option in
                        ProviderRowView(option: option)
                    }
                }
                .padding(12)
                .background(Color.mimo.surface)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mimo.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

// MARK: - Provider Count Chip

struct ProviderCountChip: View {
    let title: String
    let count: Int
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: title == L.t(AppLocalizationKey.locProviders) ? "server.rack" : "cpu")
                .interfaceFont(size: 10)
                .foregroundColor(Color.mimo.textMuted)
            Text(title)
                .interfaceFont(size: 10)
                .foregroundColor(Color.mimo.textSecondary)
            Text("\(count)")
                .interfaceFont(size: 12, weight: .semibold)
                .foregroundColor(Color.mimo.brand)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.mimo.backgroundAlt.opacity(0.5))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.mimo.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Provider Row View

struct ProviderRowView: View {
    let option: ProviderOption
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: option.isCustom ? "network.badge" : "server")
                    .interfaceFont(size: 14)
                    .foregroundColor(option.isCustom ? Color.mimo.brand : Color.mimo.textSecondary)
                
                Text(option.name)
                    .interfaceFont(size: 13, weight: .medium)
                    .foregroundColor(Color.mimo.textPrimary)
                
                Spacer()

                Toggle("", isOn: Binding(
                    get: { appState.isProviderEnabled(option.id) },
                    set: { appState.setProviderEnabled(option.id, isEnabled: $0) }
                ))
                .labelsHidden()
                .toggleStyle(.dotSized)
                .frame(width: 22, height: 18)
                .contentShape(Rectangle())
                .help(appState.isProviderEnabled(option.id)
                    ? L.t(AppLocalizationKey.locDisable)
                    : L.t(AppLocalizationKey.locEnable))

                Button(action: {
                    if option.isCustom,
                       let custom = appState.customProviders.first(where: { $0.id == option.id }) {
                        appState.removeCustomProvider(custom)
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .interfaceFont(size: 14)
                        .foregroundColor(Color.mimo.error.opacity(0.7))
                }
                .buttonStyle(HandCursorButtonStyle())
                .help(L.t(AppLocalizationKey.locRemoveProvider))
                .opacity(option.isCustom ? 1 : 0)
            }
            
            if option.isCustom,
               let custom = appState.customProviders.first(where: { $0.id == option.id }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(custom.baseURL)
                        .interfaceFont(size: 11, design: .monospaced)
                        .foregroundColor(Color.mimo.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    HStack {
                        Text(L.t(AppLocalizationKey.locModelsCount, custom.models.count))
                            .interfaceFont(size: 11)
                            .foregroundColor(Color.mimo.textSecondary)
                        
                        if custom.supportsTools {
                            Image(systemName: "checkmark.circle")
                                .interfaceFont(size: 10)
                                .foregroundColor(Color.mimo.cyan)
                        }
                        
                        if custom.acpEnabled {
                            Image(systemName: "gearshape")
                                .interfaceFont(size: 10)
                                .foregroundColor(Color.mimo.violet)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(12)
        .background(Color.mimo.surface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mimo.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Model Parameter Spoiler

struct ModelParameterSpoiler: View {
    let modelID: String
    let meta: MimoProviderModel?
    let providerID: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let meta = meta {
                VStack(alignment: .leading, spacing: 6) {
                    ParameterRow(
                        label: L.t(AppLocalizationKey.locParamContext),
                        value: ModelCapabilityLogic.contextLabel(
                            for: ContextWindowCatalog.limit(for: modelID, reported: meta.limit?.context)
                        )
                    )
                    ParameterRow(
                        label: L.t(AppLocalizationKey.locParamOutput),
                        value: "\(ContextWindowCatalog.outputLimit(for: modelID, reported: meta.limit?.output))"
                    )
                    ParameterRow(label: L.t(AppLocalizationKey.locParamReasoning), value: meta.capabilities?.reasoning == true ? L.t(AppLocalizationKey.locYes) : L.t(AppLocalizationKey.locNo))
                    ParameterRow(label: L.t(AppLocalizationKey.locParamTools), value: meta.capabilities?.toolcall != false ? L.t(AppLocalizationKey.locYes) : L.t(AppLocalizationKey.locNo))
                    ParameterRow(label: L.t(AppLocalizationKey.locParamPlan), value: meta.capabilities?.plan == true ? L.t(AppLocalizationKey.locYes) : L.t(AppLocalizationKey.locNo))

                    if let cost = meta.cost {
                        ParameterRow(label: L.t(AppLocalizationKey.locParamCost), value: "\(cost.input ?? 0)/\(cost.output ?? 0) \(L.t(AppLocalizationKey.locPer1KTokens))")
                    }

                    if let variants = meta.variants, !variants.isEmpty {
                        ParameterRow(label: L.t(AppLocalizationKey.locParamVariants), value: variants.keys.sorted().joined(separator: ", "))
                    }
                }
                .interfaceFont(size: 11)
            } else {
                Text(L.t(AppLocalizationKey.locParametersAvailable))
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textMuted)
            }
        }
        .padding(8)
        .background(Color.mimo.backgroundAlt.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private struct ParameterRow: View {
        let label: String
        let value: String
        
        var body: some View {
            HStack {
                Text(label + ":")
                    .interfaceFont(size: 10)
                    .foregroundColor(Color.mimo.textMuted)
                Spacer()
                Text(value)
                    .interfaceFont(size: 10)
                    .foregroundColor(Color.mimo.textPrimary)
            }
        }
    }
}

// MARK: - Model Detail Spoiler

struct ModelDetailSpoiler: View {
    let modelID: String
    let providerID: String
    let meta: MimoProviderModel?
    @EnvironmentObject var appState: AppState
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Text(L.t(AppLocalizationKey.locModelDetails))
                        .interfaceFont(size: 12, weight: .semibold)
                        .foregroundColor(Color.mimo.textPrimary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .interfaceFont(size: 10)
                        .foregroundColor(Color.mimo.textMuted)
                }
            }
            .buttonStyle(HandCursorButtonStyle())
            .help(isExpanded ? L.t(AppLocalizationKey.locCollapse) : L.t(AppLocalizationKey.locShow))
            
            if isExpanded, let meta = meta {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L.t(AppLocalizationKey.locConfiguration))
                        .interfaceFont(size: 11, weight: .semibold)
                        .foregroundColor(Color.mimo.textSecondary)
                    
                    ParameterDetailRow(label: "ID", value: meta.id)
                    ParameterDetailRow(label: L.t(AppLocalizationKey.locName), value: meta.name ?? "—")
                    ParameterDetailRow(label: L.t(AppLocalizationKey.locParamProvider), value: meta.providerID ?? providerID)

                    if let context = meta.limit?.context {
                        ParameterDetailRow(label: L.t(AppLocalizationKey.locParamContextLength), value: "\(context)")
                    }

                    if let capabilities = meta.capabilities {
                        ParameterDetailRow(label: L.t(AppLocalizationKey.locParamReasoning), value: capabilities.reasoning == true ? L.t(AppLocalizationKey.locSupported) : L.t(AppLocalizationKey.locNotSupported))
                        ParameterDetailRow(label: L.t(AppLocalizationKey.locParamTools), value: capabilities.toolcall != false ? L.t(AppLocalizationKey.locSupported) : L.t(AppLocalizationKey.locNotSupported))
                        ParameterDetailRow(label: L.t(AppLocalizationKey.locParamPlanMode), value: capabilities.plan == true ? L.t(AppLocalizationKey.locSupported) : L.t(AppLocalizationKey.locNotSupported))
                    }

                    if let variants = meta.variants, !variants.isEmpty {
                        ParameterDetailRow(label: L.t(AppLocalizationKey.locParamVariants), value: variants.keys.sorted().joined(separator: ", "))
                    }
                }
                .interfaceFont(size: 11)
                .padding(8)
                .background(Color.mimo.backgroundAlt)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }
    
    private struct ParameterDetailRow: View {
        let label: String
        let value: String
        
        var body: some View {
            HStack {
                Text(label)
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textMuted)
                Spacer()
                Text(value)
                    .interfaceFont(size: 11, weight: .medium)
                    .foregroundColor(Color.mimo.textPrimary)
                    .lineLimit(1)
            }
        }
    }
}
