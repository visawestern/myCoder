import SwiftUI

extension ModelSettingsProviderColumns {
    func modelDisplayRow(modelID: String, providerID: String, prefix: String?) -> some View {
        let meta = ProviderSettingsLogic.model(
            for: modelID,
            in: appState.serverProviders,
            providerID: providerID.isEmpty ? nil : providerID
        )
        let isSelected = appState.selectedModel == modelID
        let shortName = Self.splitModelID(modelID).name
        let isDisabled = isModelDisabled(modelID, providerID: providerID)
        let isCustomModel = customProvider(for: providerID) != nil
        // Context window: provider metadata when known, otherwise the
        // configured default (200k) so the user always sees a number.
        let contextTokens = ModelCapabilityLogic.effectiveContextWindow(
            for: modelID,
            in: appState.serverProviders,
            providerID: providerID.isEmpty ? nil : providerID
        )

        return HStack(spacing: 6) {
            // Every model row carries the same dot-sized switch (on = enabled).
            // Selection is expressed by the row highlight and the name colour,
            // so there is no dot and no extra checkmark.
            Toggle("", isOn: Binding(
                get: { appState.isModelEnabled(providerID: providerID, modelID: modelID) },
                set: { isEnabled in
                    toggleModelDisabled(modelID, providerID: providerID, enabled: isEnabled)
                }
            ))
            .labelsHidden()
            .toggleStyle(.dotSized)
            .frame(width: 22, height: 18)
            .contentShape(Rectangle())
            .help(isDisabled
                ? L.t(AppLocalizationKey.locEnableModel)
                : L.t(AppLocalizationKey.locDisableModel))

            // Model name
            Text(shortName)
                .interfaceFont(size: 12, weight: isSelected ? .semibold : .regular, design: .monospaced)
                .foregroundColor(isDisabled ? Color.mimo.textMuted : (isSelected ? Color.mimo.brand : Color.mimo.textPrimary))
                .strikethrough(isDisabled)
                .lineLimit(1)

            if isDisabled {
                Text(L.t(AppLocalizationKey.locDisabled))
                    .interfaceFont(size: 9, weight: .medium)
                    .foregroundColor(Color.mimo.warning)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.mimo.warning.opacity(0.12))
                    .clipShape(Capsule())
            }

            // Compact capability chips
            if meta?.capabilities?.reasoning == true {
                Text("R")
                    .interfaceFont(size: 8, weight: .bold, design: .monospaced)
                    .foregroundColor(Color.mimo.violet)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Color.mimo.violet.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            if meta?.capabilities?.toolcall != false {
                Text("T")
                    .interfaceFont(size: 8, weight: .bold, design: .monospaced)
                    .foregroundColor(Color.mimo.cyan)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Color.mimo.cyan.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            // Context window: provider metadata when known, otherwise the
            // configured default (200k) so the user always sees a number.
            Text(ModelCapabilityLogic.contextLabel(for: contextTokens))
                .interfaceFont(size: 9)
                .foregroundColor(Color.mimo.textMuted)
                .lineLimit(1)

            if meta?.cost != nil {
                Text("$")
                    .interfaceFont(size: 8, weight: .bold, design: .monospaced)
                    .foregroundColor(Color.mimo.warning)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Color.mimo.warning.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            Spacer(minLength: 4)

            // Three-dot menu
            Menu {
                // Selection is performed by clicking the full model row.
                // Keep the menu for parameters and secondary actions only.
                Button(action: {
                    openParameters(modelID: modelID, providerID: providerID)
                }) {
                    Label(L.t(AppLocalizationKey.locParameters), systemImage: "slider.horizontal.3")
                }

                if isCustomModel {
                    Button(action: {
                        beginRename(modelID, providerID: providerID)
                    }) {
                        Label(L.t(AppLocalizationKey.locRenameModel), systemImage: "pencil")
                    }
                    Button(action: {
                        beginClone(modelID, providerID: providerID)
                    }) {
                        Label(L.t(AppLocalizationKey.locCloneModel), systemImage: "plus.square.on.square")
                    }
                }

                Button(action: {
                    toggleModelDisabled(modelID, providerID: providerID)
                }) {
                    Label(
                        isDisabled ? L.t(AppLocalizationKey.locEnableModel) : L.t(AppLocalizationKey.locDisableModel),
                        systemImage: isDisabled ? "checkmark.circle" : "slash.circle"
                    )
                }

                if canDeleteModels(providerID: providerID) {
                    Divider()
                    Button(role: .destructive) {
                        deleteModel(modelID, from: providerID)
                    } label: {
                        Label(L.t(AppLocalizationKey.locDeleteModel), systemImage: "trash")
                    }
                }

                if let meta = meta {
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        let info = """
                        Model: \(meta.id)
                        Name: \(meta.name ?? "—")
                        Provider: \(meta.providerID ?? providerID)
                        Context: \(ModelCapabilityLogic.contextLabel(for: contextTokens))
                        Output: \(ContextWindowCatalog.outputLimit(for: modelID, reported: meta.limit?.output))
                        Reasoning: \(meta.capabilities?.reasoning == true ? L.t(AppLocalizationKey.locYes) : L.t(AppLocalizationKey.locNo))
                        Tools: \(meta.capabilities?.toolcall != false ? L.t(AppLocalizationKey.locYes) : L.t(AppLocalizationKey.locNo))
                        Plan: \(meta.capabilities?.plan == true ? L.t(AppLocalizationKey.locYes) : L.t(AppLocalizationKey.locNo))
                        Cost: \(meta.cost.map { "\(String(describing: $0.input))/\(String(describing: $0.output)) per 1K" } ?? "—")
                        """
                        NSPasteboard.general.setString(info, forType: .string)
                    }) {
                        Label(L.t(AppLocalizationKey.locCopyInfo), systemImage: "doc.on.doc")
                    }
                }

                // OmniRouter/agentRouter special config
                if isAgentRouterModel(modelID: modelID, providerID: providerID) {
                    Divider()
                    Button(action: {
                        toggleToolResultFix(for: modelID)
                    }) {
                        Label(
                            isToolResultFixEnabled(for: modelID) ? L.t(AppLocalizationKey.locToolResultFixOn) : L.t(AppLocalizationKey.locToolResultFixOff),
                            systemImage: isToolResultFixEnabled(for: modelID) ? "checkmark.shield.fill" : "shield.slash"
                        )
                    }
                }
            } label: {
                Image(systemName: "ellipsis.vertical")
                    .interfaceFont(size: 12, weight: .bold)
                    .foregroundColor(Color.mimo.textMuted)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(L.t(AppLocalizationKey.locActions))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            isDisabled
                ? Color.gray.opacity(0.13)
                : (isSelected ? Color.mimo.subtleFill : Color.clear)
        )
        .opacity(isDisabled ? 0.82 : 1)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.mimo.brand.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isButton)
        .onHover { inside in
            if inside {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .onTapGesture {
            guard !isSelected, !isDisabled else { return }
            if !providerID.isEmpty {
                appState.selectProvider(providerID)
            }
            appState.selectModel(modelID)
        }
    }

    // MARK: - OmniRouter / agentRouter support

    /// Определяет, является ли модель agentRouter-совместимой
    func isAgentRouterModel(modelID: String, providerID: String) -> Bool {
        let pid = providerID.lowercased()
        let mid = modelID.lowercased()
        return pid == "agentrouter" || pid == "omni" || pid == "omnirouter"
            || mid.contains("agentrouter") || mid.contains("omni")
    }

    /// Ключ UserDefaults для хранения включенности фикса формата tool result
    func toolResultFixKey(for modelID: String) -> String {
        "com.mycoder.toolResultFix.\(modelID)"
    }

    /// Проверить включен ли фикс для модели
    func isToolResultFixEnabled(for modelID: String) -> Bool {
        UserDefaults.standard.bool(forKey: toolResultFixKey(for: modelID))
    }

    /// Переключить фикс для модели
    func toggleToolResultFix(for modelID: String) {
        let key = toolResultFixKey(for: modelID)
        let current = UserDefaults.standard.bool(forKey: key)
        UserDefaults.standard.set(!current, forKey: key)
    }
}
