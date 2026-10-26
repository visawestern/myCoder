import SwiftUI

/// Manual fallback for models whose provider returned no metadata. Values from
/// the bundled catalog are shown when available; every field can be overridden
/// per provider/model and the override is stored locally.
struct ModelMetadataEditor: View {
    let modelID: String
    let providerID: String
    let serverModel: MimoProviderModel?

    @State private var override = ModelMetadataOverride()

    private var effective: MimoProviderModel? {
        ModelMetadataResolver.resolve(
            modelID: modelID,
            providerID: providerID,
            serverModel: serverModel,
            override: override.isEmpty ? nil : override
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L.t(AppLocalizationKey.locManualMetadata))
                    .interfaceFont(size: 11, weight: .semibold)
                    .foregroundColor(Color.mimo.textSecondary)
                Spacer()
                if !override.isEmpty {
                    Button(L.t(AppLocalizationKey.locResetMetadata)) {
                        ModelMetadataStore.clear(providerID: providerID, modelID: modelID)
                        override = ModelMetadataOverride()
                    }
                    .buttonStyle(HandCursorButtonStyle())
                    .interfaceFont(size: 10)
                    .foregroundColor(Color.mimo.textSecondary)
                    .help(L.t(AppLocalizationKey.locResetMetadata))
                }
            }

            HStack(spacing: 10) {
                InlineEditableField(
                    title: L.t(AppLocalizationKey.locParamContext),
                    value: effective?.limit?.context.map(String.init) ?? "",
                    placeholder: L.t(AppLocalizationKey.locDefault),
                    monospaced: true
                ) { value in
                    override.context = Int(value)
                    persist()
                }
                InlineEditableField(
                    title: L.t(AppLocalizationKey.locParamOutput),
                    value: effective?.limit?.output.map(String.init) ?? "",
                    placeholder: L.t(AppLocalizationKey.locDefault),
                    monospaced: true
                ) { value in
                    override.output = Int(value)
                    persist()
                }
            }

            InlineEditableField(
                title: L.t(AppLocalizationKey.locEffortLevels),
                value: (override.efforts ?? effective?.variants?.keys.sorted() ?? []).joined(separator: ", "),
                placeholder: L.t(AppLocalizationKey.locNoEffort),
                monospaced: true
            ) { value in
                override.efforts = value
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                persist()
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                capabilityToggle(
                    L.t(AppLocalizationKey.locParamReasoning),
                    value: effective?.capabilities?.reasoning ?? false
                ) { override.reasoning = $0; persist() }
                capabilityToggle(
                    L.t(AppLocalizationKey.locVisionInput),
                    value: effective?.capabilities?.vision ?? false
                ) { override.vision = $0; persist() }
                capabilityToggle(
                    L.t(AppLocalizationKey.locImageGeneration),
                    value: effective?.capabilities?.imagegen ?? false
                ) { override.imageGen = $0; persist() }
                capabilityToggle(
                    L.t(AppLocalizationKey.locParamTools),
                    value: effective?.capabilities?.toolcall ?? false
                ) { override.toolCall = $0; persist() }
                capabilityToggle(
                    L.t(AppLocalizationKey.locParamPlan),
                    value: effective?.capabilities?.plan ?? false
                ) { override.plan = $0; persist() }
            }
        }
        .padding(8)
        .background(Color.mimo.backgroundAlt.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .onAppear { loadOverride() }
        .onChange(of: modelID) { _ in loadOverride() }
        .onChange(of: providerID) { _ in loadOverride() }
    }

    private func capabilityToggle(
        _ title: String,
        value: Bool,
        onChange: @escaping (Bool) -> Void
    ) -> some View {
        Toggle(title, isOn: Binding(get: { value }, set: onChange))
            .toggleStyle(VuexySwitchStyle(width: 32, height: 19))
            .interfaceFont(size: 10)
            .foregroundColor(Color.mimo.textSecondary)
    }

    private func loadOverride() {
        override = ModelMetadataStore.override(providerID: providerID, modelID: modelID)
            ?? ModelMetadataOverride()
    }

    private func persist() {
        ModelMetadataStore.set(override, providerID: providerID, modelID: modelID)
    }
}
