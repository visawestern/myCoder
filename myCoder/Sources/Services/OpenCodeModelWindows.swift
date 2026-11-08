import Foundation

/// A model's context/output windows, read from the user's `opencode.json`
/// reference dictionary (`provider.<id>.models.<model>.limit.context|output`)
/// — the same source opencode itself uses. The loader is cheap and deterministic:
/// it only maps exact model ids to their declared windows, and a model without a
/// `limit` is simply absent (so the catalog falls through to suffix/family/
/// default rules).
struct ModelWindow: Equatable {
    let context: Int?
    let output: Int?
}

/// Loads the opencode reference dictionary. `load(from:)` is pure and testable;
/// the catalog keeps a cached parse of the default path so hot paths (every
/// send) do not re-read the file.
enum OpenCodeModelWindows {
    /// Standard location of the user's opencode config.
    static let defaultPath = NSHomeDirectory() + "/.config/opencode/opencode.json"

    /// Parse `provider.*.models.*` into `modelID -> ModelWindow`.
    /// Returns an empty dictionary for a missing or malformed file — a missing
    /// reference dictionary is a normal state, never a failure.
    static func load(from path: String) -> [String: ModelWindow] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let providers = root["provider"] as? [String: Any] else {
            return [:]
        }
        var result: [String: ModelWindow] = [:]
        for (_, provider) in providers {
            guard let providerDict = provider as? [String: Any],
                  let models = providerDict["models"] as? [String: Any] else { continue }
            for (modelID, model) in models {
                guard let modelDict = model as? [String: Any],
                      let limit = modelDict["limit"] as? [String: Any] else { continue }
                let context = (limit["context"] as? NSNumber)?.intValue
                let output = (limit["output"] as? NSNumber)?.intValue
                if context != nil || output != nil {
                    result[modelID] = ModelWindow(context: context, output: output)
                }
            }
        }
        return result
    }
}
