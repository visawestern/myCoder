import Foundation

/// Hosted OpenCode Zen policy for the generic OpenAI-compatible send path.
/// Zen exposes several API protocols; myCoder's direct route uses only models
/// documented for `/v1/chat/completions`. Anonymous access is intentionally
/// limited to temporary free models, while a configured Zen key unlocks the
/// curated chat-compatible paid models listed by the provider.
enum OpenCodeZenCatalog {
    static let baseURL = "https://opencode.ai/zen/v1"

    /// Paid model IDs currently documented for the OpenAI-compatible
    /// `/chat/completions` endpoint. This list is deliberately separate from
    /// the live free IDs so incompatible Responses/Messages/Gemini routes are
    /// never sent through the wrong transport.
    static let chatCompatibleModelIDs = [
        "deepseek-v4-pro",
        "deepseek-v4-flash",
        "minimax-m3",
        "minimax-m2.7",
        "minimax-m2.5",
        "glm-5.2",
        "glm-5.1",
        "glm-5",
        "kimi-k2.5",
        "kimi-k2.6",
        "kimi-k2.7-code",
        "kimi-k3"
    ]

    static func isFreeModel(_ modelID: String) -> Bool {
        MyCoderAutoFreeClient.isEligibleFreeModel(modelID)
    }

    static func availableModels(from modelIDs: [String], apiKey: String) -> [String] {
        let available = Set(modelIDs)
        let free = Array(Set(modelIDs.filter(isFreeModel)))
        let normalizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty else {
            return free.sorted()
        }
        let paidChatModels = chatCompatibleModelIDs.filter { available.contains($0) }
        return (free + paidChatModels).sorted()
    }

    static func accessSummary(hasAPIKey: Bool) -> String {
        hasAPIKey
            ? "Zen key configured · curated chat-compatible catalog"
            : "Anonymous mode · temporary free models only"
    }
}
