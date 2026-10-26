import Testing
import Foundation
@testable import myCoder

@Suite("Local memory scoring + reranker (Phase 5, 5500M, no Jev)")
struct MemoryRerankTests {

    private func chunk(_ id: String, _ body: String, daysAgo: Double = 0,
                       files: [String] = [], uses: Int = 0) -> MemoryChunk {
        MemoryChunk(id: id, title: id, body: body,
                    updatedAt: Date().addingTimeInterval(-daysAgo * 86400),
                    relatedFiles: files, useCount: uses)
    }

    private let now = Date()

    @Test func termOverlapRanksRelevantFirst() {
        let chunks = [
            chunk("a", "the project uses SQLite WAL mode for history"),
            chunk("b", "lunch preferences and weekend plans"),
        ]
        let top = MemoryScorer.selectTop(query: "SQLite WAL history",
                                         chunks: chunks, now: now,
                                         budgetTokens: 800, threshold: 0.0)
        #expect(top.first?.id == "a")
    }

    @Test func thresholdFiltersNoise() {
        let chunks = [chunk("a", "unrelated weather report")]
        let top = MemoryScorer.selectTop(query: "git rebase strategy",
                                         chunks: chunks, now: now,
                                         budgetTokens: 800, threshold: 0.2)
        #expect(top.isEmpty)
    }

    @Test func budgetCapsBytes() {
        let chunks = (0..<10).map { chunk("c\($0)", "SQLite history project database store " + String(repeating: "x", count: 500)) }
        let top = MemoryScorer.selectTop(query: "SQLite history",
                                         chunks: chunks, now: now,
                                         budgetTokens: 200, threshold: 0.0)
        let bytes = top.reduce(0) { $0 + $1.body.utf8.count }
        #expect(bytes <= 200 * 4)
        #expect(!top.isEmpty)
    }

    @Test func recencyBreaksTies() {
        let chunks = [
            chunk("old", "SQLite history", daysAgo: 60),
            chunk("new", "SQLite history", daysAgo: 0),
        ]
        let top = MemoryScorer.selectTop(query: "SQLite history",
                                         chunks: chunks, now: now,
                                         budgetTokens: 800, threshold: 0.0)
        #expect(top.first?.id == "new")
    }

    @Test func fileProximityBoosts() {
        let chunks = [
            chunk("far", "SQLite history", files: ["other/file.swift"]),
            chunk("near", "SQLite history", files: ["myCoder/Sources/Services/UsageDataPoint.swift"]),
        ]
        let top = MemoryScorer.selectTop(
            query: "SQLite history", chunks: chunks, now: now,
            openFiles: ["myCoder/Sources/Services/UsageDataPoint.swift"],
            budgetTokens: 800, threshold: 0.0)
        #expect(top.first?.id == "near")
    }

    @Test func localRerankerFailsOpenToScorerOrder() async {
        let chunks = [
            chunk("a", "SQLite WAL history"),
            chunk("b", "weather report"),
        ]
        let dead = LlamaCppReranker(transport: FailingRerankTransport(),
                                    scorerFallback: true)
        let ranked = await dead.rerank(query: "SQLite history", chunks: chunks, now: now)
        #expect(ranked.first?.id == "a")
    }

    @Test func localRerankerUsesServerOrder() async {
        let chunks = [
            chunk("a", "SQLite WAL history"),
            chunk("b", "weather report"),
        ]
        // Server prefers "b" — its order wins when reachable.
        let up = LlamaCppReranker(transport: WeatherPreferringTransport(),
                                  scorerFallback: true)
        let ranked = await up.rerank(query: "q", chunks: chunks, now: now)
        #expect(ranked.map(\.id) == ["b", "a"])
    }
}

struct FailingRerankTransport: RerankTransport {
    func score(query: String, documents: [String]) async throws -> [Double] {
        throw RerankError.unreachable("dead")
    }
}

struct WeatherPreferringTransport: RerankTransport {
    func score(query: String, documents: [String]) async throws -> [Double] {
        documents.map { $0.contains("weather") ? 0.9 : 0.1 }
    }
}
