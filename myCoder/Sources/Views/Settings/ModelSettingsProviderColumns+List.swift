import SwiftUI

extension ModelSettingsProviderColumns {
    var layoutMode: ModelSettingsLayoutMode {
        ModelSettingsLayoutLogic.mode(availableWidth: availableWidth)
    }

    var providerListColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L.t(AppLocalizationKey.locProviders))
                .interfaceFont(size: 12, weight: .semibold)
                .foregroundColor(Color.mimo.textMuted)
                .padding(.bottom, 8)

            if options.isEmpty {
                SettingsCardEmptyState(
                    icon: "server.rack",
                    title: L.t(AppLocalizationKey.locProvidersYet),
                    hint: L.t(AppLocalizationKey.locConnectTheLocalAgentAddCustomProviderGetStarted),
                    actionTitle: L.t(AppLocalizationKey.locAddProvider),
                    action: { showAddProvider = true }
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(options) { option in
                            providerOptionRow(option)
                        }
                    }
                    .id(providerRevision)
                }
            }
        }
        .settingsCardFrame()
        .padding(12)
        .background(Color.mimo.surface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mimo.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    func providerOptionRow(_ option: ProviderOption) -> some View {
        let enabled = isProviderEnabled(option)
        let isSelected = detailProviderID == option.id

        return HStack(spacing: 8) {
            // One control for every provider row — the switch is the size of
            // the old status dot (user directive: no dots, one switch).
            Toggle("", isOn: Binding(
                get: { isProviderEnabled(option) },
                set: { setProviderEnabled(option, enabled: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.dotSized)
            .frame(width: 22, height: 18)
            .contentShape(Rectangle())
            .help(enabled ? L.t(AppLocalizationKey.locDisable) : L.t(AppLocalizationKey.locEnable))

            Button(action: { selectProvider(option) }) {
                Text(option.name)
                    .interfaceFont(size: 12, weight: isSelected ? .semibold : .regular)
                    .foregroundColor(enabled ? Color.mimo.textPrimary : Color.mimo.textMuted)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HandCursorButtonStyle())

            if isMutableProvider(option) {
                Menu {
                    Button {
                        selectProvider(option)
                    } label: {
                        Label(L.t(AppLocalizationKey.locEditProvider), systemImage: "pencil")
                    }
                    Button {
                        refreshProvider(option)
                    } label: {
                        Label(L.t(AppLocalizationKey.locRefreshModels), systemImage: "arrow.clockwise")
                    }
                    Divider()
                    Button(role: .destructive) {
                        providerPendingDelete = option
                    } label: {
                        Label(L.t(AppLocalizationKey.locRemoveProvider), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .interfaceFont(size: 11, weight: .bold)
                        .foregroundColor(Color.mimo.textMuted)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(L.t(AppLocalizationKey.locActions))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            enabled
                ? (isSelected ? Color.mimo.subtleFill : Color.mimo.surface)
                : Color.gray.opacity(0.13)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.mimo.border : Color.clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .opacity(enabled ? 1 : 0.78)
        .contextMenu {
            Button(L.t(AppLocalizationKey.locEditProvider)) { selectProvider(option) }
            if isMutableProvider(option) {
                Button(L.t(AppLocalizationKey.locRefreshModels)) { refreshProvider(option) }
                Divider()
                Button(role: .destructive) { providerPendingDelete = option } label: {
                    Text(L.t(AppLocalizationKey.locRemoveProvider))
                }
            }
        }
    }
}
