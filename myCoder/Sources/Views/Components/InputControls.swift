import SwiftUI

struct AccessLevelMenu: View {
    @EnvironmentObject var appState: AppState

    private var canSelectPlan: Bool {
        ProviderCapabilityGates.canSelectPlanAgent(
            modelID: appState.effectiveSelectedModel(),
            providerID: appState.selectedProviderID.isEmpty ? nil : appState.selectedProviderID,
            providers: appState.serverProviders,
            customProviders: appState.customProviders
        )
    }

    var body: some View {
        Menu {
            ForEach(AccessLevel.allCases) { level in
                Button(action: { appState.accessLevel = level }) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: level.icon)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(level.displayName)
                                .interfaceFont(size: 12, weight: .medium)
                            Text(level.displayDescription)
                                .interfaceFont(size: 11)
                                .foregroundColor(.secondary)
                        }
                        if appState.accessLevel == level {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Divider()
            Button(action: { appState.agentMode = .plan }) {
                HStack {
                    Image(systemName: AgentMode.plan.icon)
                    Text(L.t(AppLocalizationKey.locSwitchPlanAgent))
                }
            }
            .disabled(!canSelectPlan)
            .overlay {
                if !canSelectPlan {
                    // `.help()` doesn't render on disabled controls — put the
                    // explanation on a transparent hit-testable overlay instead.
                    Color.clear.contentShape(Rectangle())
                        .help(L.t(AppLocalizationKey.locPlanModeUnavailable))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: appState.accessLevel.icon)
                    .interfaceFont(size: 11)
                Text(appState.accessLevel.displayName)
                    .interfaceFont(size: 11)
                    .lineLimit(1)
            }
            .foregroundColor(Color.mimo.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

struct AgentModeMenu: View {
    @EnvironmentObject var appState: AppState

    private var canSelectPlan: Bool {
        ProviderCapabilityGates.canSelectPlanAgent(
            modelID: appState.effectiveSelectedModel(),
            providerID: appState.selectedProviderID.isEmpty ? nil : appState.selectedProviderID,
            providers: appState.serverProviders,
            customProviders: appState.customProviders
        )
    }

    var body: some View {
        Menu {
            ForEach(AgentMode.allCases) { mode in
                Button(action: { appState.agentMode = mode }) {
                    HStack {
                        Image(systemName: mode.icon)
                        Text(mode.displayName)
                        if appState.agentMode == mode {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .disabled(mode == .plan && !canSelectPlan)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: appState.agentMode.icon)
                    .interfaceFont(size: 11)
                Text(appState.agentMode.displayName)
                    .interfaceFont(size: 11)
            }
            .foregroundColor(Color.mimo.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(canSelectPlan ? "" : (ProviderCapabilityGates.planAgentDisabledReason(
            modelID: appState.effectiveSelectedModel(),
            providerID: appState.selectedProviderID.isEmpty ? nil : appState.selectedProviderID,
            providers: appState.serverProviders,
            customProviders: appState.customProviders
        ) ?? ""))
    }
}

struct ProviderSelectorMenu: View {
    @EnvironmentObject var appState: AppState

    private var options: [ProviderOption] {
        appState.providerOptions
    }

    private var selectedName: String {
        options.first(where: { $0.id == appState.selectedProviderID })?.name ?? L.t(AppLocalizationKey.locProvider)
    }

    var body: some View {
        Menu {
            if options.isEmpty {
                Text(L.t(AppLocalizationKey.locConnectTheLocalAgentAddCustomProvider))
                    .interfaceFont(size: 11)
            } else {
                ForEach(options) { option in
                    Button(action: { appState.selectProvider(option.id) }) {
                        HStack {
                            Text(option.name)
                            if option.isCustom {
                                Text(L.t(AppLocalizationKey.locCustom))
                                    .interfaceFont(size: 10)
                                    .foregroundColor(Color.mimo.textMuted)
                            }
                            if appState.selectedProviderID == option.id {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            Divider()
            Button(L.t(AppLocalizationKey.locManageProviders)) {
                appState.showSettings = true
                appState.settingsTab = .providers
            }
        } label: {
            HStack(spacing: 4) {
                Text(selectedName)
                    .interfaceFont(size: 11)
                    .lineLimit(1)
            }
            .foregroundColor(appState.selectedProviderID.isEmpty ? Color.mimo.textMuted : Color.mimo.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

// EffortSelectorMenu and WebEffortMenu were REMOVED (user directive
// 2026-09-06): effort for web providers is discovered together with each
// model in the probe cycle and injected by the driver — there is no manual
// brain/effort control anywhere in the composer.

/// Gear button opening a popover to edit per-model call parameters
/// (plan Раздел 13 п.14) — the model menu previously opened nothing.
struct ModelParametersButton: View {
    @EnvironmentObject var appState: AppState
    @State private var isOpen = false
    @State private var params = ModelCallParameters()
    @State private var temperatureText = ""
    @State private var maxTokensText = ""
    @State private var topPText = ""
    @State private var systemText = ""
    @State private var validationMessage: String?

    var body: some View {
        Button(action: { load(); isOpen.toggle() }) {
            Image(systemName: params.isCustomized ? "slider.horizontal.3" : "slider.horizontal.below.rectangle")
                .interfaceFont(size: 11)
                .foregroundColor(params.isCustomized ? Color.mimo.brand : Color.mimo.textMuted)
        }
        .buttonStyle(HandCursorButtonStyle())
        .help(L.t(AppLocalizationKey.locModelParameters))
        .popover(isPresented: $isOpen) {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(L.t(AppLocalizationKey.locParametersFor)) — \(ModelSelectionPresentationLogic.displayModel(selectedModel: appState.selectedModel, effectiveModel: appState.effectiveSelectedModel()) ?? L.t(AppLocalizationKey.locModelPlaceholder))")
                    .interfaceFont(size: 12, weight: .semibold)
                    .foregroundColor(Color.mimo.textPrimary)
                field("Temperature (0–2)", text: $temperatureText, placeholder: L.t(AppLocalizationKey.locDefault))
                field("Max tokens", text: $maxTokensText, placeholder: L.t(AppLocalizationKey.locDefault))
                field("Top P (0–1)", text: $topPText, placeholder: L.t(AppLocalizationKey.locDefault))
                Text(L.t(AppLocalizationKey.locSystemPrompt)).interfaceFont(size: 11).foregroundColor(Color.mimo.textMuted)
                TextEditor(text: $systemText)
                    .frame(height: 60).font(.system(size: 12))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.mimo.border, lineWidth: 1))
                if let validationMessage {
                    Text(validationMessage)
                        .interfaceFont(size: 10)
                        .foregroundColor(Color.mimo.error)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button(L.t(AppLocalizationKey.locResetButton)) { resetAll() }
                        .buttonStyle(HandCursorButtonStyle()).foregroundColor(Color.mimo.error).interfaceFont(size: 11)
                    Spacer()
                    Button(L.t(AppLocalizationKey.locSave)) {
                        guard save() else { return }
                        isOpen = false
                    }
                        .buttonStyle(HandCursorButtonStyle()).foregroundColor(Color.mimo.brand).interfaceFont(size: 12, weight: .medium)
                }
            }
            .padding(14).frame(width: 260)
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).interfaceFont(size: 11).foregroundColor(Color.mimo.textMuted)
            TextField(placeholder, text: text).zcodeTextFieldStyle().interfaceFont(size: 12)
        }
    }

    private func load() {
        validationMessage = nil
        params = ModelCallParametersStore.parameters(for: ModelSelectionPresentationLogic.parameterModelID(selectedModel: appState.selectedModel, effectiveModel: appState.effectiveSelectedModel()) ?? "")
        temperatureText = params.temperature.map { String($0) } ?? ""
        maxTokensText = params.maxTokens.map { String($0) } ?? ""
        topPText = params.topP.map { String($0) } ?? ""
        systemText = params.systemPrompt ?? ""
    }

    @discardableResult
    private func save() -> Bool {
        guard let p = ModelCallParametersValidationLogic.parse(
            temperature: temperatureText,
            maxTokens: maxTokensText,
            topP: topPText,
            systemPrompt: systemText
        ) else {
            validationMessage = "Invalid values. Temperature must be 0–2, Top P must be 0–1, and Max tokens must be a positive integer."
            return false
        }
        guard let modelID = ModelSelectionPresentationLogic.parameterModelID(selectedModel: appState.selectedModel, effectiveModel: appState.effectiveSelectedModel()) else {
            validationMessage = "No model is selected."
            return false
        }
        ModelCallParametersStore.set(p, for: modelID)
        params = p
        validationMessage = nil
        return true
    }

    private func resetAll() {
        temperatureText = ""; maxTokensText = ""; topPText = ""; systemText = ""
        validationMessage = nil
        guard let modelID = ModelSelectionPresentationLogic.parameterModelID(selectedModel: appState.selectedModel, effectiveModel: appState.effectiveSelectedModel()) else { return }
        ModelCallParametersStore.set(ModelCallParameters(), for: modelID)
        params = ModelCallParameters()
    }
}

struct VariantMenu: View {
    @EnvironmentObject var appState: AppState

    private var availableVariants: [String] {
        appState.availableVariantsForSelectedModel
    }

    private var disabledReason: String? {
        ProviderCapabilityGates.variantMenuDisabledReason(
            modelID: appState.effectiveSelectedModel(),
            providerID: appState.selectedProviderID.isEmpty ? nil : appState.selectedProviderID,
            providers: appState.serverProviders,
            customProviders: appState.customProviders
        )
    }

    var body: some View {
        Menu {
            if availableVariants.isEmpty {
                Text(disabledReason ?? L.t(AppLocalizationKey.locNoVariants))
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textMuted)
            } else {
                ForEach(availableVariants, id: \.self) { variant in
                    Button(action: { appState.selectedVariant = variant }) {
                        HStack {
                            Text(ProviderSettingsLogic.variantLabel(variant))
                            if appState.selectedVariant == variant {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "slider.horizontal.3")
                    .interfaceFont(size: 11)
                Text(appState.selectedVariant.isEmpty ? L.t(AppLocalizationKey.locVariantPlaceholder) : ProviderSettingsLogic.variantLabel(appState.selectedVariant))
                    .interfaceFont(size: 11)
            }
            .foregroundColor(availableVariants.isEmpty ? Color.mimo.textMuted : Color.mimo.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(availableVariants.isEmpty)
        .help(disabledReason ?? "")
    }
}

struct CompactMessageTextField: View {
    @Environment(\.interfaceFontScale) private var interfaceFontScale
    @Binding var text: String
    let placeholder: String
    var onSubmit: (() -> Void)? = nil
    var compactSingleLine: Bool = false
    var focusRequest: Int = 0
    var maxHeightOverride: CGFloat? = nil

    private var minHeight: CGFloat {
        compactSingleLine ? InputLayout.compactTextHeight : InputLayout.textMinHeight(scale: interfaceFontScale)
    }

    private var maxHeight: CGFloat {
        maxHeightOverride ?? InputLayout.textMaxHeight(scale: interfaceFontScale)
    }

    var body: some View {
        ZeroInsetTextField(
            text: $text,
            placeholder: placeholder,
            multiline: true,
            fontSize: InterfaceTypography.scaled(14, scale: interfaceFontScale),
            minHeight: minHeight,
            maxHeight: maxHeight,
            focusRequest: focusRequest,
            onSubmit: onSubmit
        )
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct MessageInputToolbar: View {
    @Binding var messageText: String
    @Binding var showFilePicker: Bool
    @Binding var showPlusMenu: Bool
    var showPhotoPicker: Binding<Bool>? = nil
    let isLoading: Bool
    let canSend: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    /// Round 8 P1: why sending is currently blocked (shown on the send button).
    var disabledReason: String? = nil
    
    var body: some View {
        HStack(spacing: 10) {
            Button(action: { showPlusMenu = true }) {
                Image(systemName: "plus")
                    .interfaceFont(size: 16, weight: .medium)
                    .foregroundColor(Color.mimo.brand)
            }
            .buttonStyle(HandCursorButtonStyle())
            .popover(isPresented: $showPlusMenu) {
                PlusMenuView(
                    messageText: $messageText,
                    showFilePicker: $showFilePicker,
                    isPresented: $showPlusMenu,
                    showPhotoPicker: showPhotoPicker,
                    canUseTools: canUseTools
                )
            }
            
            AccessLevelMenu()

            AgentModeMenu()

            Spacer(minLength: 8)

            ProviderSelectorMenu()
            ModelPickerDropdown()
            // Model call-parameters popover (plan Раздел 13 п.14).
            if ModelSelectionPresentationLogic.shouldShowParameters(
                selectedModel: appState.selectedModel,
                effectiveModel: appState.effectiveSelectedModel()
            ) {
                ModelParametersButton()
            }
            // Audit 2026-09-06 (user directive): NO effort/brain button for
            // web providers — effort is discovered together with each model
            // (probe cycle) and injected by the driver automatically. The
            // server-variant menu also stays hidden for web providers so a
            // brain icon NEVER appears next to a web model.
            if appState.availableWebEffortsForSelectedProvider.isEmpty,
               !appState.isSelectedWebProvider,
               !appState.availableVariantsForSelectedModel.isEmpty {
                VariantMenu()
            }
            
            SendStopButton(
                isLoading: isLoading,
                canSend: canSend,
                onSend: onSend,
                onStop: onStop,
                disabledReason: disabledReason
            )
        }
    }

    @EnvironmentObject private var appState: AppState

    private var canUseTools: Bool {
        appState.supportsToolcallForSelection
    }
}

struct SendStopButton: View {
    let isLoading: Bool
    let canSend: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    /// Round 8 P1: human-readable reason the send is blocked (shown as a
    /// tooltip and via the icon color) instead of a silent no-op button.
    var disabledReason: String? = nil

    var body: some View {
        if isLoading {
            Button(action: onStop) {
                Image(systemName: "stop.circle.fill")
                    .interfaceFont(size: 24)
                    .foregroundColor(Color.mimo.error)
            }
            .buttonStyle(HandCursorButtonStyle())
            .help(L.t(AppLocalizationKey.locStopGeneration))
        } else {
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .interfaceFont(size: 24)
                    .foregroundColor(
                        canSend ? Color.mimo.brand
                        : (disabledReason != nil ? Color.mimo.error : Color.mimo.textMuted)
                    )
            }
            .buttonStyle(HandCursorButtonStyle())
            .disabled(!canSend)
            .help(disabledReason ?? L.t(AppLocalizationKey.locSendMessage))
        }
    }
}

struct WorkedTimeSeparator: View {
    let label: String
    
    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.mimo.border)
                .frame(height: 1)
            Text(label)
                .interfaceFont(size: 11)
                .foregroundColor(Color.mimo.textMuted)
            Rectangle()
                .fill(Color.mimo.border)
                .frame(height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

struct RemoteConnectionSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var host: String = ""
    @State private var port: String = ""
    @State private var isConnecting = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L.t(AppLocalizationKey.locRemoteConnection))
                .interfaceFont(size: 18, weight: .semibold)
                .foregroundColor(Color.mimo.textPrimary)
            
            Text(L.t(AppLocalizationKey.locConnectLocalAgentInstanceAnotherHost))
                .interfaceFont(size: 13)
                .foregroundColor(Color.mimo.textSecondary)
            
            HStack(spacing: 12) {
                TextField(L.t(AppLocalizationKey.locHost), text: $host)
                    .zcodeTextFieldStyle()
                TextField(L.t(AppLocalizationKey.locPort), text: $port)
                    .zcodeTextFieldStyle()
                    .frame(width: 80)
            }
            
            HStack {
                Spacer()
                Button(L.t(AppLocalizationKey.locCancel)) { dismiss() }
                    .buttonStyle(HandCursorButtonStyle())
                    .foregroundColor(Color.mimo.textSecondary)
                Button(isConnecting ? L.t(AppLocalizationKey.locConnecting) : L.t(AppLocalizationKey.locConnect)) {
                    guard let portInt = Int(port), !host.isEmpty else { return }
                    isConnecting = true
                    Task {
                        await appState.connectToServe(hostname: host, port: portInt)
                        await MainActor.run {
                            isConnecting = false
                            dismiss()
                        }
                    }
                }
                .buttonStyle(HandCursorButtonStyle())
                .foregroundColor(Color.mimo.brand)
                .disabled(host.isEmpty || port.isEmpty || isConnecting)
            }
        }
        .padding(24)
        .frame(width: 400)
        .background(Color.mimo.background)
        .onAppear {
            host = appState.serverHost
            port = String(appState.serverPort)
        }
    }
}
