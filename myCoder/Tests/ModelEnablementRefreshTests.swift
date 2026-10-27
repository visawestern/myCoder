import Testing
import Foundation
import Combine
@testable import myCoder

/// R16: switching a model or a provider off must change what the user sees in
/// the same pass. The old model row wrote the flag to `UserDefaults` and bumped
/// a local `disabledRevision` that no view ever read, so the row only refreshed
/// after the selection changed and forced an unrelated re-render.
///
/// The contract: one mutation path (`AppState.setModelEnabled` /
/// `setProviderEnabled`), state derived from the persisted store, and a
/// published signal the row, the composer and the menu all observe.
@MainActor
@Suite("R16: выключение модели и провайдера видно сразу")
struct ModelEnablementRefreshTests {

    // MARK: - Fixtures

    private func makeState() throws -> (state: AppState, defaults: UserDefaults, suite: String) {
        let suite = "mimo-enablement-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let state = AppState(defaults: defaults)
        state.serverProviders = [
            MimoProviderResponse(
                id: "p1",
                name: "Provider One",
                models: [
                    "m1": MimoProviderModel(id: "m1"),
                    "m2": MimoProviderModel(id: "m2"),
                    "m3": MimoProviderModel(id: "m3"),
                ]
            )
        ]
        state.selectedProviderID = "p1"
        state.selectedModel = "m1"
        return (state, defaults, suite)
    }

    /// Counts published changes without depending on any particular property.
    private final class ChangeCounter {
        var count = 0
        var cancellable: AnyCancellable?
    }

    // MARK: - T1: a model switch is visible immediately

    @Test("T1: выключение невыбранной модели сразу меняет её состояние и список моделей")
    func disablingModelUpdatesImmediately() throws {
        let (state, defaults, suite) = try makeState()
        defer { defaults.removePersistentDomain(forName: suite) }
        let counter = ChangeCounter()
        counter.cancellable = state.objectWillChange.sink { _ in counter.count += 1 }

        state.setModelEnabled(providerID: "p1", modelID: "m2", isEnabled: false)

        // State is read back from the store, not from a view-local copy.
        #expect(state.isModelEnabled(providerID: "p1", modelID: "m2") == false)
        #expect(DisabledModelStore.isDisabled(providerID: "p1", modelID: "m2", defaults: defaults))
        // The composer list drops it in the same pass.
        #expect(!state.modelsForSelectedProvider.contains("m2"))
        #expect(!state.availableModels.contains("m2"))
        // The selected model is untouched — disabling a neighbour must not
        // move the user's cursor.
        #expect(state.selectedModel == "m1")
        // Something observable changed, so the row re-renders without a click
        // on another model.
        #expect(counter.count > 0)
    }

    // MARK: - T2: a provider switch is visible immediately

    @Test("T2: выключение провайдера сразу меняет карточку, список моделей и композер")
    func disablingProviderUpdatesImmediately() throws {
        let (state, defaults, suite) = try makeState()
        defer { defaults.removePersistentDomain(forName: suite) }
        let counter = ChangeCounter()
        counter.cancellable = state.objectWillChange.sink { _ in counter.count += 1 }

        state.setProviderEnabled("p1", isEnabled: false)

        #expect(state.isProviderEnabled("p1") == false)
        #expect(!state.providerOptions.contains { $0.id == "p1" })
        #expect(!state.modelsForSelectedProvider.contains("m1"))
        // A dead provider must never stay selected.
        #expect(state.selectedProviderID != "p1")
        #expect(counter.count > 0)

        state.setProviderEnabled("p1", isEnabled: true)
        #expect(state.isProviderEnabled("p1"))
        #expect(state.providerOptions.contains { $0.id == "p1" })
    }

    @Test("T2: локальный провайдер читается из конфига, а не из снимка карточки")
    func localProviderReadsLiveConfig() throws {
        let suite = "mimo-enablement-local-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var config = LocalProviderConfig(kind: .ollama)
        config.isEnabled = true
        LocalProviderLogic.save([config], defaults: defaults)
        #expect(LocalProviderLogic.isEnabled(id: config.id, defaults: defaults))

        // Persisting the flag is enough for the row to show it: the row asks
        // the config, never a captured value.
        LocalProviderLogic.setEnabled(id: config.id, isEnabled: false, defaults: defaults)
        #expect(LocalProviderLogic.isEnabled(id: config.id, defaults: defaults) == false)
        #expect(LocalProviderLogic.load(defaults: defaults).first?.isEnabled == false)

        let state = AppState(defaults: defaults)
        #expect(state.isProviderEnabled(config.id) == false)
    }

    // MARK: - T3: the disabled selected model does not hang

    @Test("T3: выключение выбранной модели сразу переводит выбор на доступную")
    func disablingSelectedModelReplacesSelection() throws {
        let (state, defaults, suite) = try makeState()
        defer { defaults.removePersistentDomain(forName: suite) }

        state.setModelEnabled(providerID: "p1", modelID: "m1", isEnabled: false)

        #expect(state.selectedModel != "m1")
        #expect(state.modelsForSelectedProvider.contains(state.selectedModel))
        #expect(state.selectedModel == "m2")
        // The stored preference survives for when the model comes back.
        #expect(defaults.string(forKey: "com.mycoder.preferredModelID") != "m1")

        // The last model disabled with no alternative left clears the choice
        // instead of leaving a dead id selected.
        state.setModelEnabled(providerID: "p1", modelID: "m2", isEnabled: false)
        state.setModelEnabled(providerID: "p1", modelID: "m3", isEnabled: false)
        #expect(state.modelsForSelectedProvider.isEmpty)
        #expect(state.selectedModel.isEmpty)
    }

    // MARK: - T4: re-enabling restores the row without moving the selection

    @Test("T4: повторное включение возвращает модель в список без смены выбора")
    func reEnablingRestoresModel() throws {
        let (state, defaults, suite) = try makeState()
        defer { defaults.removePersistentDomain(forName: suite) }

        state.setModelEnabled(providerID: "p1", modelID: "m2", isEnabled: false)
        state.setModelEnabled(providerID: "p1", modelID: "m2", isEnabled: true)

        #expect(state.isModelEnabled(providerID: "p1", modelID: "m2"))
        #expect(state.modelsForSelectedProvider.contains("m2"))
        #expect(state.availableModels.contains("m2"))
        #expect(state.selectedModel == "m1")
        // Repeating the same value is a no-op, not a second toggle.
        state.setModelEnabled(providerID: "p1", modelID: "m2", isEnabled: true)
        #expect(state.isModelEnabled(providerID: "p1", modelID: "m2"))
    }

    // MARK: - T5: one path, no unread local revision

    @Test("T5: строка модели берёт состояние из AppState и не держит локальный счётчик")
    func rowReadsDerivedState() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let modelSettings = try String(
            contentsOf: root.appendingPathComponent("Sources/Views/Settings/ModelSettingsView.swift"),
            encoding: .utf8
        )
        #expect(modelSettings.contains("appState.isModelEnabled"))
        #expect(modelSettings.contains("appState.setModelEnabled"))
        #expect(!modelSettings.contains("disabledRevision"))
        #expect(!modelSettings.contains("DisabledModelStore.setDisabled"))

        let providers = try String(
            contentsOf: root.appendingPathComponent("Sources/Views/Settings/ProvidersSettingsView.swift"),
            encoding: .utf8
        )
        // The local card reads the persisted config, not the captured value it
        // was created with.
        #expect(providers.contains("appState.isProviderEnabled"))
        #expect(providers.contains("LocalProviderLogic.setEnabled(id:"))
        #expect(!providers.contains("config.isEnabled }"))
    }

    @Test("T5: единственный путь мутации — AppState, стор остаётся хранилищем")
    func singleMutationPath() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let app = try String(
            contentsOf: root.appendingPathComponent("Sources/App/MyCoderApp.swift"),
            encoding: .utf8
        )
        #expect(app.contains("func setModelEnabled(providerID:"))
        #expect(app.contains("func isModelEnabled(providerID:"))

        // Persistence layer stays pure: no notification, no UI knowledge.
        let store = try String(
            contentsOf: root.appendingPathComponent("Sources/Services/DisabledModelStore.swift"),
            encoding: .utf8
        )
        #expect(!store.contains("NotificationCenter"))
        #expect(!store.contains("SwiftUI"))
    }
}
