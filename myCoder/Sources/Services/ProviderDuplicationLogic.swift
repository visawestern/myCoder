import Foundation

enum ProviderDuplicationLogic {
    static func removingDuplicates(
        _ providers: [CustomProvider],
        apiKey: (CustomProvider) -> String = { $0.apiKey }
    ) -> [CustomProvider] {
        providers
    }

    /// Collapse duplicate provider rows. IDs are the primary key, but a
    /// server provider and a user-managed provider can expose the same
    /// display name under different IDs (for example OpenCode Serve reports
    /// `nvidia` while the app stores a custom `Nvidia` provider). In that
    /// case keep the user-managed row so rename/disable/delete stay reachable.
    static func deduplicatedOptions(_ options: [ProviderOption]) -> [ProviderOption] {
        var seenIDs = Set<String>()
        var nameIndex: [String: Int] = [:]
        var result: [ProviderOption] = []

        for option in options {
            guard seenIDs.insert(option.id.lowercased()).inserted else { continue }
            let key = normalizedName(option.name)
            guard !key.isEmpty else {
                result.append(option)
                continue
            }
            if let index = nameIndex[key] {
                if option.isCustom && !result[index].isCustom {
                    result[index] = option
                }
                continue
            }
            nameIndex[key] = result.count
            result.append(option)
        }
        return result
    }

    /// Map a provider ID to the row that survives deduplication. Used when a
    /// persisted selection points at a server row that is now represented by
    /// its user-managed duplicate.
    static func canonicalID(for providerID: String, in options: [ProviderOption]) -> String {
        guard let current = options.first(where: { $0.id == providerID }) else { return providerID }
        let key = normalizedName(current.name)
        guard !key.isEmpty else { return providerID }
        let duplicates = options.filter { normalizedName($0.name) == key }
        return duplicates.first(where: { $0.isCustom })?.id ?? providerID
    }

    private static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
