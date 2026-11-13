import Foundation
import Testing
@testable import myCoder

/// TDD for the scroll-stall fix: image-path extraction must not re-run a
/// filesystem resolve for every token on every row evaluation — the resolved
/// result is memoized per (text, project root, limit) for a short TTL.
@Suite("Image path extraction cache — memoized, TTL-bounded")
struct ChatImagePathExtractionCacheTests {

    @Test("Same text resolves once within TTL")
    func sameTextResolvesOnce() {
        let cache = ChatImagePathExtractionCache()
        var resolves = 0
        let existing = Set(["a.png", "c.png"])
        cache.resolve = { token, _ in
            resolves += 1
            return existing.contains(token) ? "/proj/\(token)" : nil
        }
        let text = "a.png b.md c.png d.txt"
        let first = cache.extractedPaths(from: text, projectRoot: "/proj", limit: 6)
        let second = cache.extractedPaths(from: text, projectRoot: "/proj", limit: 6)
        #expect(first == ["/proj/a.png", "/proj/c.png"])
        #expect(second == first)
        #expect(resolves == 4, "повторный запрос не должен резолвить токены заново")
        #expect(cache.stats.hits >= 1)
    }

    @Test("Expired entry recomputes; unchanged result still returns")
    func expiredRecomputes() {
        let cache = ChatImagePathExtractionCache()
        cache.ttl = 2
        var now = Date()
        cache.now = { now }
        var resolves = 0
        cache.resolve = { token, _ in
            resolves += 1
            return token == "a.png" ? "/proj/a.png" : nil
        }
        let text = "a.png b.md"
        _ = cache.extractedPaths(from: text, projectRoot: "/proj", limit: 4)
        now = now.addingTimeInterval(10)
        let paths = cache.extractedPaths(from: text, projectRoot: "/proj", limit: 4)
        #expect(paths == ["/proj/a.png"])
        #expect(resolves == 4, "истёкшая запись пересчитывается: 2 + 2 резолва")
        #expect(cache.stats.expired >= 1)
    }

    @Test("Different project roots are keyed separately")
    func projectRootKeyedSeparately() {
        let cache = ChatImagePathExtractionCache()
        var resolves = 0
        cache.resolve = { token, root in
            resolves += 1
            guard let root else { return nil }
            return URL(fileURLWithPath: root).appendingPathComponent(token).path
        }
        let text = "shot.png"
        let one = cache.extractedPaths(from: text, projectRoot: "/p1", limit: 2)
        let two = cache.extractedPaths(from: text, projectRoot: "/p2", limit: 2)
        #expect(one == ["/p1/shot.png"])
        #expect(two == ["/p2/shot.png"])
        #expect(resolves == 2)
    }

    @Test("Limit bounds the result set")
    func limitBindsResults() {
        let cache = ChatImagePathExtractionCache()
        cache.resolve = { token, _ in
            token.hasSuffix(".png") ? "/p/\(token)" : nil
        }
        let paths = cache.extractedPaths(
            from: "a.png b.png c.png d.png",
            projectRoot: "/p",
            limit: 2
        )
        #expect(paths == ["/p/a.png", "/p/b.png"])
    }

    @Test("Parity with real extraction on a temp project")
    func parityWithRealExtraction() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("extract-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("x".utf8).write(to: root.appendingPathComponent("shot.png"))

        let cache = ChatImagePathExtractionCache()
        let paths = cache.extractedPaths(
            from: "Смотри shot.png и missing.png",
            projectRoot: root.path,
            limit: 6
        )
        #expect(paths == [root.appendingPathComponent("shot.png").path])
    }
}
