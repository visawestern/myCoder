import SwiftUI

extension ModelSettingsProviderColumns {
    var selectedWebModel: WebProviderModel? {
        guard !parameterModelID.isEmpty,
              let web = webConfig(for: parameterProviderID) else { return nil }
        return web.discoveredModels.first(where: { $0.name == parameterModelID })
    }

    @ViewBuilder
    var modelParametersPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L.t(AppLocalizationKey.locModelParameters))
                        .interfaceFont(size: 14, weight: .semibold)
                        .foregroundColor(Color.mimo.textPrimary)
                    Text("\(parameterProviderID.isEmpty ? L.t(AppLocalizationKey.locProvider) : parameterProviderID) / \(parameterModelID)")
                        .interfaceFont(size: 10, design: .monospaced)
                        .foregroundColor(Color.mimo.textMuted)
                }
                Spacer()
                Button {
                    parameterModelID = ""
                    parameterError = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .interfaceFont(size: 15)
                        .foregroundColor(Color.mimo.textMuted)
                }
                .buttonStyle(HandCursorButtonStyle())
                .help(L.t(AppLocalizationKey.locCloseModelParameters))
                .accessibilityLabel(L.t(AppLocalizationKey.locCloseModelParameters))
            }

            if let webModel = selectedWebModel {
                webProfilePanel(webModel)
            }

            if selectedWebModel == nil {
                ModelMetadataEditor(
                    modelID: parameterModelID,
                    providerID: parameterProviderID,
                    serverModel: ProviderSettingsLogic.model(
                        for: parameterModelID,
                        in: appState.serverProviders,
                        providerID: parameterProviderID.isEmpty ? nil : parameterProviderID
                    )
                )
            }

            HStack(spacing: 10) {
                InlineEditableField(
                    title: L.t(AppLocalizationKey.locTemperature),
                    value: parameterTemperature,
                    placeholder: L.t(AppLocalizationKey.locDefault),
                    monospaced: true
                ) { value in
                    parameterTemperature = value
                    saveParameters()
                }
                InlineEditableField(
                    title: L.t(AppLocalizationKey.locMaxTokens),
                    value: parameterMaxTokens,
                    placeholder: L.t(AppLocalizationKey.locDefault),
                    monospaced: true
                ) { value in
                    parameterMaxTokens = value
                    saveParameters()
                }
                InlineEditableField(
                    title: L.t(AppLocalizationKey.locTopP),
                    value: parameterTopP,
                    placeholder: L.t(AppLocalizationKey.locDefault),
                    monospaced: true
                ) { value in
                    parameterTopP = value
                    saveParameters()
                }
            }

            InlineEditableTextArea(
                title: L.t(AppLocalizationKey.locSystemPromptOverride),
                value: parameterSystemPrompt,
                placeholder: L.t(AppLocalizationKey.locDefault)
            ) { value in
                parameterSystemPrompt = value
                saveParameters()
            }

            if let parameterError {
                Text(parameterError)
                    .interfaceFont(size: 10, weight: .medium)
                    .foregroundColor(Color.mimo.error)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text(L.t(AppLocalizationKey.locBlankValuesProviderDefaults))
                    .interfaceFont(size: 10)
                    .foregroundColor(Color.mimo.textMuted)
                Spacer()
                Button(L.t(AppLocalizationKey.locResetParameters)) { resetParameters() }
                    .buttonStyle(HandCursorButtonStyle())
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textSecondary)
                    .help(L.t(AppLocalizationKey.locResetParameters))
            }
        }
        .padding(14)
        .background(Color.mimo.surface)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.mimo.brand.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    func webProfilePanel(_ model: WebProviderModel) -> some View {
        let metadataBackground: Color = Color.mimo.backgroundAlt.opacity(0.45)
        return VStack(alignment: .leading, spacing: 7) {
            Text(L.t(AppLocalizationKey.locLiveWebProfile))
                .interfaceFont(size: 11, weight: .semibold)
                .foregroundColor(Color.mimo.textSecondary)
            HStack(spacing: 6) {
                Text(model.discoveryStatus == .active ? L.t(AppLocalizationKey.locActive) : L.t(model.discoveryStatus.rawValue))
                    .interfaceFont(size: 10, weight: .medium)
                    .foregroundColor(model.discoveryStatus == .active ? Color.mimo.success : Color.mimo.warning)
                Text(model.parameterProfile.availableKeys.isEmpty ? L.t(AppLocalizationKey.locNoParameterControls) : model.parameterProfile.availableKeys.joined(separator: ", "))
                    .interfaceFont(size: 10, design: .monospaced)
                    .foregroundColor(Color.mimo.textMuted)
                    .lineLimit(2)
            }
            let detected = model.parameterProfile.values
            Text(L.t(AppLocalizationKey.locDetectedDefaults, "temperature \(detected.temperature.map { String(describing: $0) } ?? "—") · max tokens \(detected.maxTokens.map { String(describing: $0) } ?? "—") · top P \(detected.topP.map { String(describing: $0) } ?? "—")"))
                .interfaceFont(size: 10, design: .monospaced)
                .foregroundColor(Color.mimo.textMuted)
                .lineLimit(2)
            if !model.parameterProfile.labels.isEmpty {
                Text(L.t(AppLocalizationKey.locDetectedLabels, model.parameterProfile.labels.joined(separator: ", ")))
                    .interfaceFont(size: 10)
                    .foregroundColor(Color.mimo.textMuted)
                    .lineLimit(2)
            }
        }
        .padding(8)
        .background(metadataBackground)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    func openParameters(modelID: String, providerID: String) {
        parameterModelID = modelID
        parameterProviderID = providerID
        let params = ModelCallParametersStore.parameters(for: modelID)
        parameterTemperature = params.temperature.map { String($0) } ?? ""
        parameterMaxTokens = params.maxTokens.map { String($0) } ?? ""
        parameterTopP = params.topP.map { String($0) } ?? ""
        parameterSystemPrompt = params.systemPrompt ?? ""
        parameterError = nil
    }

    func resetParameters() {
        parameterTemperature = ""
        parameterMaxTokens = ""
        parameterTopP = ""
        parameterSystemPrompt = ""
        saveParameters()
    }

    func saveParameters() {
        guard !parameterModelID.isEmpty else { return }
        let trimmedTemperature = parameterTemperature.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMaxTokens = parameterMaxTokens.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTopP = parameterTopP.trimmingCharacters(in: .whitespacesAndNewlines)
        let temperature = trimmedTemperature.isEmpty ? nil : Double(trimmedTemperature)
        let maxTokens = trimmedMaxTokens.isEmpty ? nil : Int(trimmedMaxTokens)
        let topP = trimmedTopP.isEmpty ? nil : Double(trimmedTopP)
        guard trimmedTemperature.isEmpty || temperature != nil,
              trimmedMaxTokens.isEmpty || maxTokens != nil,
              trimmedTopP.isEmpty || topP != nil else {
            parameterError = L.t(AppLocalizationKey.locUseNumericParameters)
            return
        }
        if let temperature, !(0...2).contains(temperature) {
            parameterError = L.t(AppLocalizationKey.locTemperatureRange)
            return
        }
        if let maxTokens, maxTokens <= 0 {
            parameterError = L.t(AppLocalizationKey.locMaxTokensRange)
            return
        }
        if let topP, !(0...1).contains(topP) {
            parameterError = L.t(AppLocalizationKey.locTopPRange)
            return
        }
        ModelCallParametersStore.set(
            ModelCallParameters(
                temperature: temperature,
                maxTokens: maxTokens,
                topP: topP,
                systemPrompt: {
                    let trimmed = parameterSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }()
            ),
            for: parameterModelID
        )
        parameterError = nil
    }

    /// Разделить modelID на префикс (провайдер) и имя модели
    /// Например "oc/deepseek" → ("oc", "deepseek"), "gpt-4" → (nil, "gpt-4")
    static func splitModelID(_ modelID: String) -> (prefix: String?, name: String) {
        ModelGroupingLogic.splitModelID(modelID)
    }
}
