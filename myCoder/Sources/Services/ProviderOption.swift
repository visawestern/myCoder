import Foundation

/// A single row in the unified Providers list (server + custom + local).
/// Extracted to its own file so both ProviderSettingsLogic and
/// LocalProviderConfig can share it without a heavy dependency chain
/// (plan Раздел 1 Блок 1 п.6).
struct ProviderOption: Equatable, Identifiable {
    let id: String
    let name: String
    let isCustom: Bool
    let isConnected: Bool
}
