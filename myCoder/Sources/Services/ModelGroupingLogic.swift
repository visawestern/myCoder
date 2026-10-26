import Foundation

/// Model ids carry an optional provider prefix (`oc/deepseek`, `gpt-4`).
/// The prefix is the grouping key used by the settings model list and by the
/// composer's model dropdown.
enum ModelGroupingLogic {
    static func splitModelID(_ modelID: String) -> (prefix: String?, name: String) {
        if let slashIndex = modelID.firstIndex(of: "/") {
            let prefix = String(modelID[..<slashIndex])
            let name = String(modelID[modelID.index(after: slashIndex)...])
            return (prefix.isEmpty ? nil : prefix, name)
        }
        return (nil, modelID)
    }

    static func groupedModels(_ models: [String]) -> [(prefix: String?, models: [String])] {
        var grouped: [(String?, [String])] = []
        var seenPrefixes = Set<String>()
        for modelID in models {
            let (prefix, _) = splitModelID(modelID)
            let groupKey = prefix ?? ""
            if seenPrefixes.contains(groupKey) { continue }
            seenPrefixes.insert(groupKey)
            grouped.append((prefix, models.filter { (splitModelID($0).prefix ?? "") == groupKey }))
        }
        return grouped
    }

    static func groupKey(prefix: String?, providerID: String) -> String {
        "\(providerID)::\(prefix ?? "__all__")"
    }
}

/// One capability badge rendered next to a model name.
struct ModelCapabilityBadge: Equatable, Identifiable {
    enum Kind: String, Equatable {
        case thinking
        case tools
        case plan
        case vision
        case imagegen
    }

    let kind: Kind
    let systemImage: String
    let label: String

    var id: String { kind.rawValue }
}

/// Model metadata shown as small badges under the model name.
enum ModelCapabilityLogic {
    static func badges(
        for modelID: String,
        in providers: [MimoProviderResponse],
        providerID: String? = nil
    ) -> [ModelCapabilityBadge] {
        let capabilities = ProviderSettingsLogic.model(
            for: modelID,
            in: providers,
            providerID: providerID
        )?.capabilities
        guard let capabilities else { return [] }
        var badges: [ModelCapabilityBadge] = []
        if capabilities.reasoning == true {
            badges.append(ModelCapabilityBadge(kind: .thinking, systemImage: "brain.head.profile", label: "Thinking"))
        }
        if capabilities.toolcall != false {
            badges.append(ModelCapabilityBadge(kind: .tools, systemImage: "wrench.and.screwdriver", label: "Tools"))
        }
        if capabilities.plan == true {
            badges.append(ModelCapabilityBadge(kind: .plan, systemImage: "map", label: "Plan"))
        }
        if capabilities.vision == true {
            badges.append(ModelCapabilityBadge(kind: .vision, systemImage: "eye", label: "Vision"))
        }
        if capabilities.imagegen == true {
            badges.append(ModelCapabilityBadge(kind: .imagegen, systemImage: "photo", label: "Image generation"))
        }
        return badges
    }

    static func contextWindow(
        for modelID: String,
        in providers: [MimoProviderResponse],
        providerID: String? = nil
    ) -> Int? {
        ProviderSettingsLogic.model(
            for: modelID,
            in: providers,
            providerID: providerID
        )?.limit?.context
    }

    static func contextLabel(for tokens: Int) -> String {
        guard tokens > 0 else { return "" }
        if tokens >= 1_000_000 {
            let millions = Double(tokens) / 1_000_000
            return millions == millions.rounded()
                ? "\(Int(millions))M"
                : String(format: "%.1fM", millions)
        }
        let thousands = tokens / 1000
        return thousands > 0 ? "\(thousands)k" : "\(tokens)"
    }
}
