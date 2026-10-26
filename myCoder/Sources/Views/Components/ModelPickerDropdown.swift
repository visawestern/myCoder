import SwiftUI

/// Custom model dropdown for the composer. Models are grouped by provider
/// prefix exactly like the settings model list, and every model carries a
/// second line with small capability badges and its context window.
struct ModelPickerDropdown: View {
    @EnvironmentObject var appState: AppState
    @State private var isOpen = false
    @State private var collapsedGroups: Set<String> = []

    private var models: [String] {
        appState.modelsForSelectedProvider
    }

    private var groups: [(prefix: String?, models: [String])] {
        ModelGroupingLogic.groupedModels(models)
    }

    private var displayName: String? {
        ModelSelectionPresentationLogic.displayModel(
            selectedModel: appState.selectedModel,
            effectiveModel: appState.effectiveSelectedModel()
        )
    }

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(displayName ?? L.t(AppLocalizationKey.locModelPlaceholder))
                    .interfaceFont(size: 11)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .interfaceFont(size: 8, weight: .semibold)
            }
            .foregroundColor(displayName == nil ? Color.mimo.textMuted : Color.mimo.textSecondary)
        }
        .buttonStyle(HandCursorButtonStyle())
        .fixedSize()
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            dropdownContent
        }
    }

    private var dropdownContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if appState.selectedProviderID.isEmpty {
                Text(L.t(AppLocalizationKey.locSelectProviderFirst))
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textMuted)
                    .padding(12)
            } else if models.isEmpty {
                Text(L.t(AppLocalizationKey.locModelsForThisProvider))
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textMuted)
                    .padding(12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(groups.indices, id: \.self) { index in
                            groupSection(groups[index])
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 320)
                Divider()
                Button {
                    isOpen = false
                    appState.showSettings = true
                    appState.settingsTab = .providers
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                            .interfaceFont(size: 10)
                        Text(L.t(AppLocalizationKey.locManageModels))
                            .interfaceFont(size: 11)
                        Spacer()
                    }
                    .foregroundColor(Color.mimo.brand)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(HandCursorButtonStyle())
            }
        }
        .frame(width: 330)
        .background(Color.mimo.background)
    }

    private func groupSection(_ group: (prefix: String?, models: [String])) -> some View {
        let key = ModelGroupingLogic.groupKey(prefix: group.prefix, providerID: appState.selectedProviderID)
        let isCollapsed = collapsedGroups.contains(key)
        return VStack(alignment: .leading, spacing: 3) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    if isCollapsed {
                        collapsedGroups.remove(key)
                    } else {
                        collapsedGroups.insert(key)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isCollapsed ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
                        .interfaceFont(size: 10, weight: .semibold)
                        .foregroundColor(Color.mimo.brand)
                    Image(systemName: "cube.fill")
                        .interfaceFont(size: 9)
                        .foregroundColor(Color.mimo.textMuted)
                    Text(group.prefix ?? L.t(AppLocalizationKey.locAllModels))
                        .interfaceFont(size: 10, weight: .semibold, design: .monospaced)
                        .foregroundColor(Color.mimo.textSecondary)
                    Text(L.t(AppLocalizationKey.locModelsCount, group.models.count))
                        .interfaceFont(size: 9)
                        .foregroundColor(Color.mimo.textMuted)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.mimo.backgroundAlt)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
            }
            .buttonStyle(HandCursorButtonStyle())

            if !isCollapsed {
                VStack(spacing: 2) {
                    ForEach(group.models, id: \.self) { modelID in
                        modelRow(modelID)
                    }
                }
            }
        }
    }

    private func modelRow(_ modelID: String) -> some View {
        let isSelected = ModelSelectionPresentationLogic.isSelected(
            candidate: modelID,
            selectedModel: appState.selectedModel,
            effectiveModel: appState.effectiveSelectedModel()
        )
        let badges = ModelCapabilityLogic.badges(
            for: modelID,
            in: appState.serverProviders,
            providerID: appState.selectedProviderID.isEmpty ? nil : appState.selectedProviderID
        )
        let context = ModelCapabilityLogic.contextWindow(
            for: modelID,
            in: appState.serverProviders,
            providerID: appState.selectedProviderID.isEmpty ? nil : appState.selectedProviderID
        )
        return Button {
            appState.selectModel(modelID)
            isOpen = false
        } label: {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .interfaceFont(size: 10)
                    .foregroundColor(isSelected ? Color.mimo.brand : Color.mimo.textMuted.opacity(0.6))
                    .frame(width: 12)
                VStack(alignment: .leading, spacing: 3) {
                    Text(ModelGroupingLogic.splitModelID(modelID).name)
                        .interfaceFont(size: 11, weight: isSelected ? .semibold : .regular, design: .monospaced)
                        .foregroundColor(isSelected ? Color.mimo.brand : Color.mimo.textPrimary)
                        .lineLimit(1)
                    if !badges.isEmpty || context != nil {
                        HStack(spacing: 4) {
                            ForEach(badges) { badge in
                                badgeView(badge)
                            }
                            if let context {
                                Text(ModelCapabilityLogic.contextLabel(for: context))
                                    .interfaceFont(size: 8, weight: .medium, design: .monospaced)
                                    .foregroundColor(Color.mimo.textMuted)
                                    .padding(.horizontal, 3)
                                    .padding(.vertical, 1)
                                    .background(Color.mimo.textMuted.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                    .help("Context window: \(ModelCapabilityLogic.contextLabel(for: context))")
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.mimo.brand.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(HandCursorButtonStyle())
    }

    private func badgeView(_ badge: ModelCapabilityBadge) -> some View {
        Image(systemName: badge.systemImage)
            .interfaceFont(size: 8, weight: .medium)
            .foregroundColor(Color.mimo.textMuted)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(Color.mimo.textMuted.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .help(badge.label)
    }
}
