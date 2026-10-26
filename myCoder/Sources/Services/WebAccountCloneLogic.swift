import Foundation

/// Round 30b — "Add account" semantics for the web-provider vendor tiles.
///
/// The tile used to be a dead button once the vendor had any configuration
/// (`guard !providers.contains else { return }`), so a second account of the
/// same vendor could not be created from the UI even though
/// `POST /api/add-account` supported cloning. Now the first click creates the
/// default config and every next click clones the most recent account with a
/// fresh id/name and NO session state (cookies are never copied between
/// accounts).
enum WebAccountCloneLogic {

    struct Outcome {
        /// True when there was no existing config: `config` is a fresh default.
        let isNewDefault: Bool
        let config: WebProviderConfig
    }

    static func next(for vendor: WebChatVendor,
                     in providers: [WebProviderConfig]) -> Outcome {
        let existing = providers.filter { $0.vendor == vendor }
        guard let source = existing.last else {
            return Outcome(isNewDefault: true, config: WebProviderConfig(vendor: vendor))
        }
        // Strip any previous "(Account N)" suffix so clones of clones stay
        // clean: "Kimi (Account 2)" → base "Kimi" → "Kimi (Account 3)".
        let baseName: String
        if let range = source.displayName.range(of: " \\(Account [0-9]+\\)$", options: .regularExpression) {
            baseName = String(source.displayName[..<range.lowerBound])
        } else {
            baseName = source.displayName
        }
        let clone = WebProviderConfig(
            id: UUID().uuidString,
            vendor: source.vendor,
            displayName: "\(baseName) (Account \(existing.count + 1))",
            transport: source.transport,
            chatURL: source.chatURL,
            cookieStorePath: nil,
            systemPrompt: source.systemPrompt,
            selectedModel: "",
            effort: source.effort,
            toolCallDelayMs: source.toolCallDelayMs,
            sessionKeepAliveSec: source.sessionKeepAliveSec,
            autoLogin: source.autoLogin,
            headless: source.headless,
            maxToolIterations: source.maxToolIterations,
            acknowledgedToS: source.acknowledgedToS
        )
        return Outcome(isNewDefault: false, config: clone)
    }
}
