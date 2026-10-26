import Foundation

enum ProviderDuplicationLogic {
    static func isDuplicateOfBuiltInAutoFree(
        _ provider: CustomProvider,
        apiKey: String
    ) -> Bool {
        guard provider.type == .openCodeZen else { return false }
        guard apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard !provider.requiresAPIKey else { return false }
        let baseURL = provider.baseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard baseURL == OpenCodeZenCatalog.baseURL else { return false }
        return provider.models.allSatisfy { MyCoderAutoFreeClient.isEligibleFreeModel($0) }
    }

    static func removingDuplicates(
        _ providers: [CustomProvider],
        apiKey: (CustomProvider) -> String = { $0.apiKey }
    ) -> [CustomProvider] {
        providers.filter { !isDuplicateOfBuiltInAutoFree($0, apiKey: apiKey($0)) }
    }

    static func deduplicatedOptions(_ options: [ProviderOption]) -> [ProviderOption] {
        var seen = Set<String>()
        return options.filter { seen.insert($0.id.lowercased()).inserted }
    }
}
