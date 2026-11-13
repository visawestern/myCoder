import AppKit
import Foundation

/// Live counters of the base64 decode cache (tests assert no repeated work).
struct ChatBase64ImageStats {
    var hits = 0
    var decodes = 0
    var stores = 0
    var evictions = 0
}

/// Memoized, bounded cache of decoded message attachments (base64 payloads).
///
/// Input: a base64 image payload.
/// Output: the decoded `NSImage`, or nil for undecodable payloads.
/// Purpose: fixing the scroll stall — `TappableChatImage` decoded `Data`
/// + `NSImage(data:)` on the main thread every time a lazy row
/// re-materialized. Identical payloads are decoded once and reused.
/// Dependencies: injectable `decode` (production uses `Data`/`NSImage`).
final class ChatBase64ImageCache {
    static let shared = ChatBase64ImageCache()

    /// Maximum cached images before LRU eviction.
    var maxEntries = 96
    /// Injectable decoder — production decodes base64 → NSImage.
    var decode: (String) -> NSImage? = { payload in
        guard let data = Data(base64Encoded: payload) else { return nil }
        return NSImage(data: data)
    }

    private(set) var stats = ChatBase64ImageStats()

    private var cache: [String: NSImage] = [:]
    private var order: [String] = []
    private let lock = NSLock()

    /// Internal so tests can create isolated instances; production uses `shared`.
    init() {}

    /// Decoded image for `base64`, cached by the exact payload string.
    func image(forBase64 base64: String) -> NSImage? {
        lock.lock()
        if let hit = cache[base64] {
            stats.hits += 1
            lock.unlock()
            return hit
        }
        lock.unlock()

        guard let image = decode(base64) else { return nil }

        lock.lock()
        defer { lock.unlock() }
        if cache[base64] == nil {
            cache[base64] = image
            order.append(base64)
            stats.decodes += 1
            stats.stores += 1
            while cache.count > maxEntries, order.count > 1 {
                let victim = order.removeFirst()
                if cache.removeValue(forKey: victim) != nil {
                    stats.evictions += 1
                }
            }
        }
        return image
    }

    /// Clear state (tests).
    func resetForTesting() {
        lock.lock()
        cache.removeAll()
        order.removeAll()
        stats = ChatBase64ImageStats()
        lock.unlock()
    }
}
