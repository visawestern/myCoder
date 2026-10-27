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

    // MARK: - Family grouping

    /// Tokens that describe a role, a format or a precision — never the model
    /// line itself (`codegemma-1.1-7b-instruct` belongs to `codegemma`).
    static let roleTokens: Set<String> = [
        "instruct", "it", "chat", "coder", "code", "base", "preview", "latest",
        "thinking", "reasoning", "free", "turbo", "mini", "nano", "small",
        "medium", "large", "embed", "embedding", "vision", "vl", "rerank",
        "tts", "stt", "imggen", "omni", "moe", "flash", "swift", "ultra",
        "pro", "max", "exp", "experimental", "hf", "gguf", "safetensors",
        "text", "completion", "chatml", "raw", "sft", "dpo", "rlhf",
    ]

    /// Quantization / precision markers that are stripped from the family key.
    static let quantizationTokens: Set<String> = [
        "fp8", "fp16", "bf16", "fp32", "int4", "int8", "awq", "gptq", "q4",
        "q5", "q6", "q8", "q4_k_m", "q4_k_s", "q5_k_m", "q6_k", "q8_0", "exl2",
        "mxfp4", "nf4", "w4a16", "w8a8", "w8a16", "bfloat16", "float16",
    ]

    /// The model line a model id belongs to: the part that stays the same for
    /// all variants (`codegemma-1.1-7b` and `codegemma-7b` → `codegemma`).
    /// A version glued to the name (`qwen3.8`) is kept — it is a new line.
    static func familyKey(for modelID: String) -> String {
        let (_, name) = splitModelID(modelID)
        let lowered = name.lowercased()
        guard !lowered.isEmpty else { return lowered }

        var tokens = lowered
            .split(separator: "-", omittingEmptySubsequences: true)
            .map { String($0) }
            .filter { !quantizationTokens.contains($0) }
            .filter { !roleTokens.contains($0) }

        // Size and version markers are only meaningful at the tail.
        // Iterate: drop trailing size, then trailing version, then trailing
        // size again (in case a version removal exposed a size).
        var changed = true
        while changed {
            changed = false
            while let last = tokens.last, isSizeToken(last) {
                tokens.removeLast()
                changed = true
            }
            while tokens.count > 1, let last = tokens.last, isVersionToken(last) {
                tokens.removeLast()
                changed = true
            }
        }

        guard !tokens.isEmpty else { return lowered }
        return tokens.joined(separator: "-")
    }

    /// Models grouped by their family, keeping the incoming order.
    static func groupedByFamily(_ models: [String]) -> [(family: String, models: [String])] {
        var order: [String] = []
        var buckets: [String: [String]] = [:]
        for model in models {
            let family = familyKey(for: model)
            if buckets[family] == nil {
                buckets[family] = []
                order.append(family)
            }
            buckets[family]?.append(model)
        }
        return order.map { (family: $0, models: buckets[$0] ?? []) }
    }

    /// `7b`, `1.5b`, `30b-a3b` style parameter markers. Also accepts `m`
    /// (millions) suffix and optional `a` prefix (e.g. `a800m`).
    static func isSizeToken(_ token: String) -> Bool {
        var candidate = token
        if candidate.hasPrefix("a") { candidate.removeFirst() }
        guard candidate.hasSuffix("b") || candidate.hasSuffix("m") else { return false }
        candidate.removeLast()
        guard !candidate.isEmpty else { return false }
        let parts = candidate.split(separator: ".", omittingEmptySubsequences: true)
        guard !parts.isEmpty, parts.count <= 2 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isNumber }
        }
    }

    /// `1.1`, `v2`, `v4.1`, `4v`, `3.1v` style version markers.
    static func isVersionToken(_ token: String) -> Bool {
        var candidate = token
        if candidate.hasPrefix("v") { candidate.removeFirst() }
        // Allow an optional single trailing letter (e.g. "4v" → "4").
        if candidate.last?.isLetter == true { candidate.removeLast() }
        guard !candidate.isEmpty else { return false }
        let parts = candidate.split(separator: ".", omittingEmptySubsequences: true)
        guard !parts.isEmpty else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isNumber }
        }
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

    /// Effective context window of a model: the provider metadata when it
    /// exists, otherwise the configured default (200k).
    static func effectiveContextWindow(
        for modelID: String,
        in providers: [MimoProviderResponse],
        providerID: String? = nil
    ) -> Int {
        let reported = contextWindow(for: modelID, in: providers, providerID: providerID)
        return ContextWindowCatalog.limit(for: modelID, reported: reported)
    }

    /// Effective output limit of a model: the provider metadata when it
    /// exists, otherwise the configured default (32k).
    static func effectiveOutputLimit(
        for modelID: String,
        in providers: [MimoProviderResponse],
        providerID: String? = nil
    ) -> Int {
        let reported = ProviderSettingsLogic.model(
            for: modelID,
            in: providers,
            providerID: providerID
        )?.limit?.output
        return ContextWindowCatalog.outputLimit(for: modelID, reported: reported)
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
