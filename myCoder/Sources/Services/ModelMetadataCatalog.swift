import Foundation

/// Independent, bundled model metadata catalog generated from the public
/// models.dev registry cached by OpenCode. The app never guesses values: a
/// missing entry stays missing and can be filled manually per provider/model.
struct ModelMetadataCatalog: Sendable {
    struct Entry: Decodable, Sendable {
        let id: String
        let name: String?
        let context: Int?
        let output: Int?
        let reasoning: Bool?
        let toolCall: Bool?
        let vision: Bool?
        let imageGen: Bool?
        let plan: Bool?
        let efforts: [String]?
        let costInput: Double?
        let costOutput: Double?
    }

    private struct Document: Decodable {
        let models: [String: Entry]
    }

    private let models: [String: Entry]

    init(data: Data) {
        let document = (try? JSONDecoder().decode(Document.self, from: data))
        models = document?.models ?? [:]
    }

    init(models: [String: Entry]) {
        self.models = models
    }

    static let shared: ModelMetadataCatalog = {
        // The catalog ships as a SwiftPM target resource (module bundle), but a
        // hand-assembled app bundle can also place it in Contents/Resources.
        // Try both so a packaging change cannot silently empty the catalog.
        let candidates = [
            Bundle.module.url(forResource: "model_metadata", withExtension: "json"),
            Bundle.main.url(forResource: "model_metadata", withExtension: "json")
        ].compactMap { $0 }
        guard let url = candidates.first,
              let data = try? Data(contentsOf: url) else {
            // Never fail silently: without the catalog every model would show
            // "Not reported" and look like missing provider data.
            FileHandle.standardError.write(
                Data("model_metadata.json is missing from the app bundle; model metadata falls back to provider responses and user overrides.\n".utf8)
            )
            return ModelMetadataCatalog(models: [:])
        }
        return ModelMetadataCatalog(data: data)
    }()

    func lookup(modelID: String) -> MimoProviderModel? {
        guard let entry = entry(for: modelID) else { return nil }
        var variants: [String: MimoModelVariant]?
        if let efforts = entry.efforts, !efforts.isEmpty {
            variants = Dictionary(uniqueKeysWithValues: efforts.map {
                ($0, MimoModelVariant(reasoningEffort: $0))
            })
        }
        let cost: MimoModelCost? = {
            guard entry.costInput != nil || entry.costOutput != nil else { return nil }
            return MimoModelCost(input: entry.costInput, output: entry.costOutput)
        }()
        return MimoProviderModel(
            id: entry.id,
            name: entry.name,
            providerID: nil,
            capabilities: MimoModelCapabilities(
                reasoning: entry.reasoning,
                toolcall: entry.toolCall,
                plan: entry.plan,
                vision: entry.vision,
                imagegen: entry.imageGen
            ),
            variants: variants,
            limit: (entry.context != nil || entry.output != nil)
                ? MimoModelLimit(context: entry.context, output: entry.output)
                : nil,
            cost: cost
        )
    }

    func entry(for modelID: String) -> Entry? {
        for candidate in Self.candidates(for: modelID) {
            if let match = models[candidate] { return match }
        }
        return nil
    }

    static func candidates(for modelID: String) -> [String] {
        let raw = modelID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !raw.isEmpty else { return [] }
        var seeds: [String] = [raw]
        if let slash = raw.lastIndex(of: "/") {
            seeds.append(String(raw[raw.index(after: slash)...]))
        }
        var result: [String] = []
        for seed in seeds {
            let value = seed
            var pending = [value]
            var seen = Set<String>()
            while let current = pending.popLast() {
                guard seen.insert(current).inserted else { continue }
                result.append(current)
                for suffix in [":free", "-free", ":latest", "-latest"] where current.hasSuffix(suffix) {
                    pending.append(String(current.dropLast(suffix.count)))
                }
                if let dateRange = current.range(of: #"[-:]\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) {
                    pending.append(String(current[..<dateRange.lowerBound]))
                }
                if let compactDate = current.range(of: #"[-:]\d{8}$"#, options: .regularExpression) {
                    pending.append(String(current[..<compactDate.lowerBound]))
                }
            }
        }
        return result
    }
}

struct ModelMetadataOverride: Codable, Equatable, Sendable {
    var context: Int?
    var output: Int?
    var reasoning: Bool?
    var toolCall: Bool?
    var vision: Bool?
    var imageGen: Bool?
    var plan: Bool?
    var efforts: [String]?

    init(
        context: Int? = nil,
        output: Int? = nil,
        reasoning: Bool? = nil,
        toolCall: Bool? = nil,
        vision: Bool? = nil,
        imageGen: Bool? = nil,
        plan: Bool? = nil,
        efforts: [String]? = nil
    ) {
        self.context = context
        self.output = output
        self.reasoning = reasoning
        self.toolCall = toolCall
        self.vision = vision
        self.imageGen = imageGen
        self.plan = plan
        self.efforts = efforts
    }

    var isEmpty: Bool {
        context == nil && output == nil && reasoning == nil && toolCall == nil
            && vision == nil && imageGen == nil && plan == nil && efforts == nil
    }
}

enum ModelMetadataStore {
    static let storageKey = "com.mycoder.modelMetadataOverrides"
    private static let separator = "\u{1F}"

    static func key(providerID: String, modelID: String) -> String {
        providerID + separator + modelID
    }

    static func loadAll(defaults: UserDefaults = .standard) -> [String: ModelMetadataOverride] {
        guard let data = defaults.data(forKey: storageKey),
              let map = try? JSONDecoder().decode([String: ModelMetadataOverride].self, from: data) else {
            return [:]
        }
        return map
    }

    static func override(
        providerID: String,
        modelID: String,
        defaults: UserDefaults = .standard
    ) -> ModelMetadataOverride? {
        loadAll(defaults: defaults)[key(providerID: providerID, modelID: modelID)]
    }

    static func set(
        _ override: ModelMetadataOverride,
        providerID: String,
        modelID: String,
        defaults: UserDefaults = .standard
    ) {
        var map = loadAll(defaults: defaults)
        if override.isEmpty {
            map.removeValue(forKey: key(providerID: providerID, modelID: modelID))
        } else {
            map[key(providerID: providerID, modelID: modelID)] = override
        }
        if let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: storageKey)
        }
    }

    static func clear(providerID: String, modelID: String, defaults: UserDefaults = .standard) {
        var map = loadAll(defaults: defaults)
        map.removeValue(forKey: key(providerID: providerID, modelID: modelID))
        if map.isEmpty {
            defaults.removeObject(forKey: storageKey)
        } else if let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: storageKey)
        }
    }
}

enum ModelMetadataResolver {
    static func resolve(
        modelID: String,
        providerID: String,
        serverModel: MimoProviderModel?,
        catalog: ModelMetadataCatalog = .shared,
        override: ModelMetadataOverride? = nil
    ) -> MimoProviderModel? {
        let base = serverModel ?? catalog.lookup(modelID: modelID)
        guard let override else { return base }
        guard base != nil || !override.isEmpty else { return nil }

        let baseCapabilities = base?.capabilities
        let capabilities = MimoModelCapabilities(
            reasoning: override.reasoning ?? baseCapabilities?.reasoning,
            toolcall: override.toolCall ?? baseCapabilities?.toolcall,
            plan: override.plan ?? baseCapabilities?.plan,
            vision: override.vision ?? baseCapabilities?.vision,
            imagegen: override.imageGen ?? baseCapabilities?.imagegen
        )
        let limit: MimoModelLimit? = {
            guard override.context != nil || override.output != nil
                    || base?.limit?.context != nil || base?.limit?.output != nil else { return nil }
            return MimoModelLimit(
                context: override.context ?? base?.limit?.context,
                output: override.output ?? base?.limit?.output
            )
        }()
        let variants: [String: MimoModelVariant]? = {
            guard let efforts = override.efforts else { return base?.variants }
            guard !efforts.isEmpty else { return nil }
            return Dictionary(uniqueKeysWithValues: efforts.map {
                ($0, MimoModelVariant(reasoningEffort: $0))
            })
        }()

        return MimoProviderModel(
            id: base?.id ?? modelID,
            name: base?.name,
            providerID: base?.providerID ?? providerID,
            capabilities: capabilities,
            variants: variants,
            limit: limit,
            cost: base?.cost
        )
    }
}
