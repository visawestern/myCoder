import Foundation

/// Rerank transport: scores documents against a query (higher = better).
/// Implementations: `URLSessionRerankTransport` (llama.cpp server on the
/// 5500M, Phase 5) — tests inject fakes through this seam.
protocol RerankTransport {
    func score(query: String, documents: [String]) async throws -> [Double]
}

enum RerankError: Error, Equatable {
    case unreachable(String)
    case badResponse(String)
}

/// llama.cpp server transport (`POST {baseURL}/rerank` with
/// `{query, documents}` → `{scores}`). Thin by design: batching, timeouts
/// and model choice live in `scripts/setup-reranker.sh` + server flags.
struct URLSessionRerankTransport: RerankTransport {
    let baseURL: URL
    let session: URLSession

    init(baseURL: URL = URL(string: "http://127.0.0.1:8080")!,
         session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func score(query: String, documents: [String]) async throws -> [Double] {
        var request = URLRequest(url: baseURL.appendingPathComponent("rerank"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "query": query, "documents": documents,
        ])
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw RerankError.unreachable(error.localizedDescription)
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw RerankError.badResponse("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scores = json["scores"] as? [Double],
              scores.count == documents.count else {
            throw RerankError.badResponse("expected {scores:[n]} for n documents")
        }
        return scores
    }
}

/// Local reranker with fail-open fallback (Phase 5 decision: no Jev).
/// Server order wins when reachable; on any transport failure the turn
/// keeps the local scorer order instead of losing context.
struct LlamaCppReranker {
    let transport: RerankTransport
    /// When false, transport errors propagate instead of falling back.
    let scorerFallback: Bool

    init(transport: RerankTransport = URLSessionRerankTransport(),
         scorerFallback: Bool = true) {
        self.transport = transport
        self.scorerFallback = scorerFallback
    }

    func rerank(query: String, chunks: [MemoryChunk], now: Date = Date(),
                openFiles: [String] = []) async -> [MemoryChunk] {
        guard chunks.count > 1 else { return chunks }
        do {
            let scores = try await transport.score(query: query, documents: chunks.map(\.body))
            guard scores.count == chunks.count else { throw RerankError.badResponse("count mismatch") }
            return zip(chunks, scores).sorted { $0.1 > $1.1 }.map(\.0)
        } catch {
            guard scorerFallback else { return chunks }
            return chunks.sorted {
                MemoryScorer.score(query: query, openFiles: openFiles, chunk: $0, now: now)
                    > MemoryScorer.score(query: query, openFiles: openFiles, chunk: $1, now: now)
            }
        }
    }
}
