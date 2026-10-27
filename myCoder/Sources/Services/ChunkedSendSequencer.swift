import Foundation

/// How the parts of one compiled context reach the remote model.
enum ChunkSendStrategy: Equatable {
    /// One paid request: every part travels as its own user message.
    case singleRequest
    /// Sequential paid requests: one part per request, the model is told to
    /// wait for all parts (user directive D6).
    case sequentialRequests
}

/// Decides how the chunks of a compiled context are delivered.
enum ChunkedSendSequencer {

    /// OpenAI-compatible endpoints accept several user messages in one
    /// request — one paid round trip. Web/ACP/serve routes answer per
    /// request, so their parts go one by one (D6).
    static func strategy(for route: SendRoute) -> ChunkSendStrategy {
        switch route {
        case .web, .acp, .mimoServe, .openCodeServe:
            return .sequentialRequests
        case .openAICompatible, .autoFree, .none:
            return .singleRequest
        }
    }

    /// The texts to deliver, in order.
    static func payloads(for chunks: [PromptChunk], strategy: ChunkSendStrategy) -> [String] {
        guard !chunks.isEmpty else { return [] }
        guard chunks.count > 1 else { return [chunks[0].text] }
        switch strategy {
        case .singleRequest:
            return chunks.map(\.text)
        case .sequentialRequests:
            let total = chunks.count
            return chunks.enumerated().map { offset, chunk in
                let index = offset + 1
                if index == 1 {
                    return "[часть 1/\(total) — контекст приходит несколькими сообщениями; дождись всех частей и только потом отвечай]\n" + chunk.text
                }
                if index == total {
                    return "[последняя часть \(total)/\(total) — контекст получен полностью, теперь отвечай]\n" + chunk.text
                }
                return chunk.text
            }
        }
    }

    /// One text with every part — for routes that take a single user message.
    static func combinedText(for chunks: [PromptChunk], strategy: ChunkSendStrategy) -> String {
        payloads(for: chunks, strategy: strategy).joined(separator: "\n\n")
    }
}
