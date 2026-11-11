import Foundation

/// Доступность веб-провайдера в селекторе чата (plan Раздел 13 п.4).
/// Вход считается подтверждённым только после живой проверки страницы
/// AntiBrowser; отметка хранится в `WebProviderConfig.loginConfirmedAt`.
/// Файлов cookie на диске больше нет — постоянный профиль браузера хранит
/// сессию сам.
enum WebProviderConnectivity {
    /// Whether a web provider is connected: its login was confirmed by a live
    /// page check. Legal acknowledgement is not a runtime connectivity gate.
    static func isConnected(_ config: WebProviderConfig) -> Bool {
        config.loginConfirmedAt != nil
    }

    /// Chat-input provider options for connected web providers, so they appear
    /// alongside local/custom providers in the send-message provider selector.
    static func providerOptions(_ configs: [WebProviderConfig]) -> [ProviderOption] {
        configs
            .filter { isConnected($0) }
            .filter { !models(for: $0).isEmpty }
            .map { ProviderOption(id: "web:\($0.id)", name: "🌐 \($0.displayName)",
                                  isCustom: true, isConnected: true) }
    }

    /// The models offered by a web provider. Only live-discovered or explicitly
    /// configured models are valid; catalog lists are not used as guesses for a
    /// changing third-party UI.
    static func models(for config: WebProviderConfig) -> [String] {
        config.allModels
    }

    /// Whether the given provider option id refers to a web provider.
    static func isWebProviderID(_ id: String) -> Bool { id.hasPrefix("web:") }

    /// Extract the WebProviderConfig id from an option id.
    static func configID(fromOptionID id: String) -> String? {
        guard id.hasPrefix("web:") else { return nil }
        return String(id.dropFirst("web:".count))
    }

    /// Connection summary shown once connected (plan Раздел 13 п.4).
    static func connectionSummary(_ config: WebProviderConfig, connected: Bool) -> String {
        guard connected else { return "Not connected — confirm the browser login first." }
        let modelCount = models(for: config).count
        let runtime = WebTransportRuntimeLogic.label(for: config.transport)
        return "\(runtime) · \(modelCount) models · delay \(config.toolCallDelayMs)ms"
    }
}
