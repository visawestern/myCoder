import SwiftUI

extension ModelSettingsProviderColumns {
    var modelsColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L.t(AppLocalizationKey.locModels))
                    .interfaceFont(size: 12, weight: .semibold)
                    .foregroundColor(Color.mimo.textMuted)
                Spacer()
                Menu {
                    ForEach(ModelSortOrder.allCases) { order in
                        Button {
                            modelSortOrder = order
                        } label: {
                            Label(order.title, systemImage: modelSortOrder == order ? "checkmark" : "arrow.up.arrow.down")
                        }
                    }
                } label: {
                    Label(L.t(AppLocalizationKey.locSortModels, modelSortOrder.title), systemImage: "arrow.up.arrow.down")
                        .interfaceFont(size: 10, weight: .medium)
                        .foregroundColor(Color.mimo.brand)
                }
                .menuStyle(.borderlessButton)
                .help(L.t(AppLocalizationKey.locSortModels, modelSortOrder.title))
            }

            let providerID = detailProviderID.isEmpty ? appState.selectedProviderID : detailProviderID
            let allModels = models(for: providerID)
            let filteredModels = visibleModelIDs(allModels, providerID: providerID)
            let familyGroups = ModelGroupingLogic.groupedByFamily(filteredModels)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textMuted)
                TextField(L.t(AppLocalizationKey.locFilterModels), text: $modelSearchQuery)
                    .textFieldStyle(.plain)
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textPrimary)
                if !modelSearchQuery.isEmpty {
                    Button {
                        modelSearchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .interfaceFont(size: 10)
                            .foregroundColor(Color.mimo.textMuted)
                    }
                    .buttonStyle(HandCursorButtonStyle())
                    .help(L.t(AppLocalizationKey.locCancel))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(Color.mimo.background)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.mimo.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            if allModels.isEmpty {
                SettingsCardEmptyState(
                    icon: "cpu",
                    title: L.t(AppLocalizationKey.locModelsLoaded),
                    hint: providerID.isEmpty
                        ? L.t(AppLocalizationKey.locSelectProviderToBrowseModels)
                        : L.t(AppLocalizationKey.locStartLocalAgentOrCheck)
                )
            } else if filteredModels.isEmpty {
                Text(L.t(AppLocalizationKey.locNoModelsMatchFilter))
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textMuted)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        // Models are grouped by their common family
                        // (codegemma-1.1-7b + codegemma-7b → "codegemma").
                        ForEach(familyGroups, id: \.family) { group in
                            if group.models.count > 1 {
                                modelFamilyHeader(family: group.family, count: group.models.count)
                            }
                            if !collapsedModelFamilies.contains(group.family) {
                                ForEach(group.models, id: \.self) { modelID in
                                    compactModelCard(modelID: modelID, providerID: providerID, prefix: nil)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 320)
            }

            if customProvider(for: providerID) != nil {
                HStack(spacing: 6) {
                    if newModelProviderID == providerID {
                        TextField(L.t(AppLocalizationKey.locModelID), text: $newModelDraft)
                            .textFieldStyle(.plain)
                            .interfaceFont(size: 11, design: .monospaced)
                            .foregroundColor(Color.mimo.textPrimary)
                            .onSubmit { commitAddModel(providerID: providerID) }
                        Button(action: { commitAddModel(providerID: providerID) }) {
                            Image(systemName: "checkmark")
                                .interfaceFont(size: 11, weight: .semibold)
                                .foregroundColor(Color.mimo.success)
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(HandCursorButtonStyle())
                        .help(L.t(AppLocalizationKey.locSave))
                        Button(action: {
                            newModelProviderID = ""
                            newModelDraft = ""
                        }) {
                            Image(systemName: "xmark")
                                .interfaceFont(size: 11, weight: .semibold)
                                .foregroundColor(Color.mimo.textMuted)
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(HandCursorButtonStyle())
                        .help(L.t(AppLocalizationKey.locCancel))
                    } else {
                        Button {
                            newModelProviderID = providerID
                            newModelDraft = ""
                        } label: {
                            Label(L.t(AppLocalizationKey.locAddCustomModel), systemImage: "plus")
                                .interfaceFont(size: 11, weight: .medium)
                                .foregroundColor(Color.mimo.brand)
                        }
                        .buttonStyle(HandCursorButtonStyle())
                        .help(L.t(AppLocalizationKey.locAddCustomModel))
                        Spacer()
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.mimo.background)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.mimo.border, lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

        }
        .settingsCardFrame()
        .padding(12)
        .background(Color.mimo.surface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mimo.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    func visibleModelIDs(_ models: [String], providerID: String) -> [String] {
        let query = modelSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = query.isEmpty ? models : models.filter { modelID in
            let meta = ProviderSettingsLogic.model(
                for: modelID,
                in: appState.serverProviders,
                providerID: providerID.isEmpty ? nil : providerID
            )
            return modelID.localizedCaseInsensitiveContains(query)
                || (meta?.name?.localizedCaseInsensitiveContains(query) == true)
        }
        return filtered.sorted { lhs, rhs in
            switch modelSortOrder {
            case .name:
                return Self.splitModelID(lhs).name.localizedCaseInsensitiveCompare(Self.splitModelID(rhs).name) == .orderedAscending
            case .context:
                let left = ProviderSettingsLogic.model(for: lhs, in: appState.serverProviders, providerID: providerID.isEmpty ? nil : providerID)?.limit?.context ?? -1
                let right = ProviderSettingsLogic.model(for: rhs, in: appState.serverProviders, providerID: providerID.isEmpty ? nil : providerID)?.limit?.context ?? -1
                return left == right ? lhs < rhs : left > right
            case .reasoning:
                let left = ProviderSettingsLogic.model(for: lhs, in: appState.serverProviders, providerID: providerID.isEmpty ? nil : providerID)?.capabilities?.reasoning == true
                let right = ProviderSettingsLogic.model(for: rhs, in: appState.serverProviders, providerID: providerID.isEmpty ? nil : providerID)?.capabilities?.reasoning == true
                return left == right ? lhs < rhs : left && !right
            case .tools:
                let left = ProviderSettingsLogic.model(for: lhs, in: appState.serverProviders, providerID: providerID.isEmpty ? nil : providerID)?.capabilities?.toolcall != false
                let right = ProviderSettingsLogic.model(for: rhs, in: appState.serverProviders, providerID: providerID.isEmpty ? nil : providerID)?.capabilities?.toolcall != false
                return left == right ? lhs < rhs : left && !right
            }
        }
    }

    /// Header of a model family (e.g. "codegemma · 2 models"). Clicking it
    /// folds the family away so long lists stay readable.
    func modelFamilyHeader(family: String, count: Int) -> some View {
        let isCollapsed = collapsedModelFamilies.contains(family)
        return Button {
            if isCollapsed {
                collapsedModelFamilies.remove(family)
            } else {
                collapsedModelFamilies.insert(family)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.right")
                    .interfaceFont(size: 8, weight: .bold)
                    .foregroundColor(Color.mimo.textMuted)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                Text(family)
                    .interfaceFont(size: 11, weight: .semibold)
                    .foregroundColor(Color.mimo.textSecondary)
                Text("\(count)")
                    .interfaceFont(size: 9, weight: .medium)
                    .foregroundColor(Color.mimo.textMuted)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.mimo.surface)
                    .clipShape(Capsule())
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(HandCursorButtonStyle())
    }

    @ViewBuilder
    func compactModelCard(modelID: String, providerID: String, prefix: String?) -> some View {
        if isEditingModel(modelID: modelID, providerID: providerID) {
            modelEditRow(modelID: modelID, providerID: providerID)
        } else if isEditingClone(modelID: modelID, providerID: providerID) {
            modelCloneRow(sourceModelID: modelID, providerID: providerID)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                modelDisplayRow(modelID: modelID, providerID: providerID, prefix: prefix)
                if parameterModelID == modelID {
                    modelParametersPanel
                        .padding(.leading, 18)
                        .padding(.bottom, 2)
                }
            }
        }
    }

    func modelCloneRow(sourceModelID: String, providerID: String) -> some View {
        HStack(spacing: 6) {
            TextField(L.t(AppLocalizationKey.locModelID), text: $cloneModelDraft)
                .textFieldStyle(.plain)
                .interfaceFont(size: 11, design: .monospaced)
                .foregroundColor(Color.mimo.textPrimary)
                .onSubmit { commitClone(sourceModelID: sourceModelID, providerID: providerID) }
            Button(action: { commitClone(sourceModelID: sourceModelID, providerID: providerID) }) {
                Image(systemName: "checkmark")
                    .interfaceFont(size: 11, weight: .semibold)
                    .foregroundColor(Color.mimo.success)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HandCursorButtonStyle())
            .help(L.t(AppLocalizationKey.locSave))
            Button(action: {
                cloneSourceModelID = ""
                cloneModelProviderID = ""
                cloneModelDraft = ""
            }) {
                Image(systemName: "xmark")
                    .interfaceFont(size: 11, weight: .semibold)
                    .foregroundColor(Color.mimo.textMuted)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HandCursorButtonStyle())
            .help(L.t(AppLocalizationKey.locCancel))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.mimo.subtleFill)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    func modelEditRow(modelID: String, providerID: String) -> some View {
        HStack(spacing: 6) {
            TextField(L.t(AppLocalizationKey.locModelID), text: $editingModelDraft)
                .textFieldStyle(.plain)
                .interfaceFont(size: 11, design: .monospaced)
                .foregroundColor(Color.mimo.textPrimary)
                .onSubmit { commitRename(modelID: modelID, providerID: providerID) }
            Button(action: { commitRename(modelID: modelID, providerID: providerID) }) {
                Image(systemName: "checkmark")
                    .interfaceFont(size: 11, weight: .semibold)
                    .foregroundColor(Color.mimo.success)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HandCursorButtonStyle())
            .help(L.t(AppLocalizationKey.locSave))
            Button(action: { cancelRename() }) {
                Image(systemName: "xmark")
                    .interfaceFont(size: 11, weight: .semibold)
                    .foregroundColor(Color.mimo.textMuted)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HandCursorButtonStyle())
            .help(L.t(AppLocalizationKey.locCancel))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.mimo.subtleFill)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
