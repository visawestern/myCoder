import Foundation

/// Sends one prompt to a local model and returns its raw answer.
protocol LocalCompilerTransporting {
    func complete(candidate: LocalModelCandidate, prompt: String, system: String?) async throws -> String
}

/// Live transport: an OpenAI-compatible local server (Ollama, STRATA) reached
/// with the same client the chat path uses — no streaming, no tools, one turn.
struct LiveLocalCompilerTransport: LocalCompilerTransporting {
    let timeout: TimeInterval

    init(timeout: TimeInterval = 300) {
        self.timeout = timeout
    }

    func complete(candidate: LocalModelCandidate, prompt: String, system: String?) async throws -> String {
        var messages: [DirectChatMessage] = []
        if let system, !system.isEmpty {
            messages.append(DirectChatMessage(role: "system", content: system))
        }
        messages.append(DirectChatMessage(role: "user", content: prompt))
        let result = try await DirectChatClient.send(
            baseURL: candidate.baseURL,
            apiKey: candidate.apiKey,
            model: candidate.model,
            messages: messages,
            transport: URLSessionDirectChatTransport(timeout: timeout)
        )
        return result.content
    }
}

/// Walks the user's local model list and returns the first successful answer.
/// A model that fails (unreachable, empty answer) is skipped — the next model
/// in the list is used (user directive D3).
struct LocalModelRunner {
    struct Outcome: Equatable {
        let text: String
        let candidate: LocalModelCandidate
    }

    let directory: LocalModelDirectory
    let transport: LocalCompilerTransporting

    func run(prompt: String, system: String?) async throws -> Outcome {
        guard !directory.candidates.isEmpty else { throw LocalCompilerError.noLocalModels }
        var lastError = LocalCompilerError.noLocalModels
        for candidate in directory.candidates {
            do {
                let text = try await transport.complete(candidate: candidate, prompt: prompt, system: system)
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lastError = .emptyResponse(model: candidate.model)
                    continue
                }
                return Outcome(text: text, candidate: candidate)
            } catch let error as LocalCompilerError {
                lastError = error
            } catch {
                lastError = .transportFailed(model: candidate.model, reason: error.localizedDescription)
            }
        }
        throw lastError
    }
}
