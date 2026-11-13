import Foundation

/// Live counters of the extraction cache (tests assert no repeated work).
struct ChatImagePathExtractionStats {
    var hits = 0
    var misses = 0
    var resolves = 0
    var expired = 0
    var evictions = 0
}

/// Memoized, TTL-bounded cache of image-path extraction results.
///
/// Input: message text, project root, result limit.
/// Output: the same ordered, deduplicated absolute image paths that a fresh
/// extraction would produce — but only re-running the filesystem resolver when
/// the entry is absent or expired.
/// Purpose: fixing the scroll stall — `ChatImagePathLogic.extractImagePaths`
/// resolved every whitespace token against the filesystem on the main thread
/// on every row evaluation. Repeated evaluations of the same text are now a
/// dictionary hit for a short TTL.
/// Dependencies: injectable `resolve` (production: `ChatFileOpenLogic.resolveFilePath`).
final class ChatImagePathExtractionCache {
    static let shared = ChatImagePathExtractionCache()

    struct Key: Hashable {
        let text: String
        let projectRoot: String?
        let limit: Int
    }

    private struct Entry {
        let paths: [String]
        let createdAt: Date
    }

    /// How long a cached result is trusted without re-resolution.
    var ttl: TimeInterval = 3.0
    /// Maximum cached entries before LRU eviction.
    var maxEntries = 64
    /// Injectable clock (tests advance it to exercise TTL expiry).
    var now: () -> Date = { Date() }
    /// Injectable token resolver — production uses the real filesystem.
    var resolve: (String, String?) -> String? = {
        ChatFileOpenLogic.resolveFilePath($0, projectRoot: $1)
    }

    private(set) var stats = ChatImagePathExtractionStats()

    private var cache: [Key: Entry] = [:]
    private var order: [Key] = []
    private let lock = NSLock()

    /// Internal so tests can create isolated instances; production uses `shared`.
    init() {}

    /// Extracted image paths for `text`, cached by (text, project root, limit).
    func extractedPaths(from text: String, projectRoot: String?, limit: Int) -> [String] {
        let key = Key(text: text, projectRoot: projectRoot, limit: limit)
        lock.lock()
        stats.expired += pruneExpiredLocked()
        if let entry = cache[key], now().timeIntervalSince(entry.createdAt) <= ttl {
            stats.hits += 1
            lock.unlock()
            return entry.paths
        }
        lock.unlock()

        var resolvedCount = 0
        let paths = ChatImagePathLogic.resolvedPaths(
            in: text,
            projectRoot: projectRoot,
            limit: limit
        ) { token in
            resolvedCount += 1
            return resolve(token, projectRoot)
        }

        lock.lock()
        stats.resolves += resolvedCount
        stats.misses += 1
        cache[key] = Entry(paths: paths, createdAt: now())
        order.append(key)
        while cache.count > maxEntries, order.count > 1 {
            let victim = order.removeFirst()
            if cache.removeValue(forKey: victim) != nil {
                stats.evictions += 1
            }
        }
        lock.unlock()
        return paths
    }

    /// Drop expired entries (caller holds the lock). Returns how many were
    /// removed so the caller can count them in `stats`.
    private func pruneExpiredLocked() -> Int {
        let cutoff = now().addingTimeInterval(-ttl)
        var removed = 0
        for (key, entry) in cache where entry.createdAt < cutoff {
            cache.removeValue(forKey: key)
            if let index = order.firstIndex(of: key) {
                order.remove(at: index)
            }
            removed += 1
        }
        return removed
    }

    /// Clear state (tests).
    func resetForTesting() {
        lock.lock()
        cache.removeAll()
        order.removeAll()
        stats = ChatImagePathExtractionStats()
        lock.unlock()
    }
}
