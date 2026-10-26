import SwiftUI

/// Assigns the ordered list of models used for myCoder's background work.
/// Replaces the old hardcoded "myCoder Auto Free" provider card: free models
/// remain available as one source, but every provider is treated equally.
struct InternalModelsSection: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var store = InternalModelStore.shared
    @ObservedObject private var freeStore = MyCoderAutoFreeStore.shared
    @State private var isRefreshingFree = false

    private var customProviders: [CustomProvider] {
        appState.customProviders
    }

    private var localProviders: [LocalProviderConfig] {
        LocalProviderLogic.load()
    }

    private var freeModels: [String] {
        let catalog = freeStore.provider.models.map(\.id)
        return catalog.isEmpty ? MyCoderAutoFreeClient.freeModelIDs : catalog
    }

    /// Live server catalog while connected, persisted catalog otherwise so
    /// internal server models survive a restart before the server reconnects.
    private var serverProviders: [MimoProviderResponse]? {
        appState.serverProviders.isEmpty ? nil : appState.serverProviders
    }

    private var availableRefs: [InternalModelRef] {
        InternalModelResolver.availableModels(
            customProviders: customProviders,
            localProviders: localProviders,
            freeModels: freeModels,
            serverProviders: serverProviders
        )
    }

    private var unselectedRefs: [InternalModelRef] {
        availableRefs.filter { !store.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.t(AppLocalizationKey.locInternalModels))
                        .interfaceFont(size: 18, weight: .semibold)
                        .foregroundColor(Color.mimo.textPrimary)
                    Text(L.t(AppLocalizationKey.locInternalModelsDescription))
                        .interfaceFont(size: 12)
                        .foregroundColor(Color.mimo.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                addMenu
            }

            if store.models.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.t(AppLocalizationKey.locNoInternalModels))
                        .interfaceFont(size: 12, weight: .semibold)
                        .foregroundColor(Color.mimo.textPrimary)
                    Text(L.t(AppLocalizationKey.locInternalModelsHint))
                        .interfaceFont(size: 10)
                        .foregroundColor(Color.mimo.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.mimo.background)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mimo.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(store.models.enumerated()), id: \.element.id) { index, ref in
                        modelRow(ref, index: index)
                    }
                }
            }

            Text(L.t(AppLocalizationKey.locInternalModelsHint))
                .interfaceFont(size: 10)
                .foregroundColor(Color.mimo.textMuted)
        }
        .padding(16)
        .background(Color.mimo.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.mimo.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onReceive(NotificationCenter.default.publisher(for: .providersChanged)) { _ in
            pruneMissingModels()
        }
    }

    private var addMenu: some View {
        Menu {
            let groups = groupedUnselected()
            if groups.isEmpty {
                Text(L.t("All available models are already assigned"))
            } else {
                ForEach(groups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.refs, id: \.id) { ref in
                            Button {
                                store.add(ref)
                            } label: {
                                Text(ref.modelID)
                            }
                        }
                    }
                }
            }
            if freeModels.isEmpty {
                Divider()
                Button {
                    refreshFreeModels()
                } label: {
                    Label(L.t(AppLocalizationKey.locRefreshModels), systemImage: "arrow.clockwise")
                }
                .disabled(isRefreshingFree)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                Text(L.t(AppLocalizationKey.locAddInternalModel))
            }
            .interfaceFont(size: 12, weight: .medium)
            .foregroundColor(Color.mimo.brand)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .buttonStyle(HandCursorButtonStyle())
        .help(L.t(AppLocalizationKey.locAddInternalModel))
    }

    private func groupedUnselected() -> [(title: String, refs: [InternalModelRef])] {
        let refs = unselectedRefs
        var order: [String] = []
        var byTitle: [String: [InternalModelRef]] = [:]
        for ref in refs {
            let title = InternalModelResolver.displayName(
                for: ref,
                customProviders: customProviders,
                localProviders: localProviders,
                serverProviders: serverProviders
            )
            if byTitle[title] == nil {
                order.append(title)
                byTitle[title] = []
            }
            byTitle[title, default: []].append(ref)
        }
        return order.map { ($0, byTitle[$0, default: []]) }
    }

    private func modelRow(_ ref: InternalModelRef, index: Int) -> some View {
        let providerName = InternalModelResolver.displayName(
            for: ref,
            customProviders: customProviders,
            localProviders: localProviders,
            serverProviders: serverProviders
        )
        let isFree = ref.providerID == MyCoderAutoFreeProvider.builtInID
        let isAvailable = InternalModelResolver.route(
            for: ref,
            customProviders: customProviders,
            localProviders: localProviders,
            serverProviders: serverProviders
        ) != nil

        return HStack(spacing: 8) {
            Text("\(index + 1)")
                .interfaceFont(size: 10, weight: .bold, design: .monospaced)
                .foregroundColor(Color.mimo.textMuted)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(ref.modelID)
                    .interfaceFont(size: 12, weight: .medium, design: .monospaced)
                    .foregroundColor(Color.mimo.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(providerName)
                        .interfaceFont(size: 9)
                        .foregroundColor(Color.mimo.textMuted)
                    if isFree {
                        Text(L.t(AppLocalizationKey.locFree))
                            .interfaceFont(size: 8, weight: .bold)
                            .foregroundColor(Color.mimo.success)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.mimo.success.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    if !isAvailable {
                        Text(L.t("Unavailable"))
                            .interfaceFont(size: 8, weight: .medium)
                            .foregroundColor(Color.mimo.warning)
                    }
                }
            }

            Spacer(minLength: 6)

            Button {
                store.move(ref, offset: -1)
            } label: {
                Image(systemName: "chevron.up")
                    .interfaceFont(size: 9, weight: .semibold)
                    .foregroundColor(index == 0 ? Color.mimo.textMuted.opacity(0.35) : Color.mimo.textMuted)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HandCursorButtonStyle())
            .disabled(index == 0)
            .help(L.t(AppLocalizationKey.locMoveUp))

            Button {
                store.move(ref, offset: 1)
            } label: {
                Image(systemName: "chevron.down")
                    .interfaceFont(size: 9, weight: .semibold)
                    .foregroundColor(index == store.models.count - 1 ? Color.mimo.textMuted.opacity(0.35) : Color.mimo.textMuted)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HandCursorButtonStyle())
            .disabled(index == store.models.count - 1)
            .help(L.t(AppLocalizationKey.locMoveDown))

            Button(role: .destructive) {
                store.remove(ref)
            } label: {
                Image(systemName: "xmark")
                    .interfaceFont(size: 9, weight: .semibold)
                    .foregroundColor(Color.mimo.error)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HandCursorButtonStyle())
            .help(L.t(AppLocalizationKey.locRemoveProvider))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isAvailable ? Color.mimo.background : Color.gray.opacity(0.13))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.mimo.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .opacity(isAvailable ? 1 : 0.78)
    }

    private func pruneMissingModels() {
        let valid = Set(availableRefs)
        let filtered = store.models.filter { valid.contains($0) }
        if filtered.count != store.models.count {
            store.replaceAll(filtered)
        }
    }

    private func refreshFreeModels() {
        guard !isRefreshingFree else { return }
        isRefreshingFree = true
        Task {
            _ = await freeStore.refreshModels()
            await MainActor.run { isRefreshingFree = false }
        }
    }
}
