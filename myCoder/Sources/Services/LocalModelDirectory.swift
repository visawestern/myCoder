import Foundation

/// One local model that can act as the context compiler: the user's own
/// machine, their own model list, free to run.
struct LocalModelCandidate: Equatable {
    let providerID: String
    let providerName: String
    /// OpenAI-compatible base URL (Ollama/STRATA expose `/v1`).
    let baseURL: String
    let apiKey: String?
    let model: String
}

/// The ordered list of local models the user configured. The order is exactly
/// the order in the settings ("как есть") — the runner walks it and takes the
/// next model when one fails (user directive D3).
struct LocalModelDirectory: Equatable {
    let candidates: [LocalModelCandidate]

    var isEmpty: Bool { candidates.isEmpty }
}

enum LocalModelDirectoryBuilder {
    /// Builds the directory from the configured local providers.
    ///
    /// Only OpenAI-compatible local providers take part: an OpenCode-kind
    /// server answers through a session API, and a compiler turn must never
    /// create a visible chat session in the user's history.
    static func build(localProviders: [LocalProviderConfig]) -> LocalModelDirectory {
        var candidates: [LocalModelCandidate] = []
        for provider in localProviders where provider.isEnabled {
            guard provider.kind == .ollama || provider.kind == .strata else { continue }
            let baseURL = "\(provider.apiBaseURL)/v1"
            let name = provider.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let providerName = (name?.isEmpty == false) ? name! : provider.kind.displayName
            for model in provider.models {
                let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                candidates.append(LocalModelCandidate(
                    providerID: provider.id,
                    providerName: providerName,
                    baseURL: baseURL,
                    apiKey: nil,
                    model: trimmed
                ))
            }
        }
        return LocalModelDirectory(candidates: candidates)
    }
}
