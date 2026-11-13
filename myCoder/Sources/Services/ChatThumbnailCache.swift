import AppKit
import Foundation

/// File identity used to detect whether an image file changed on disk.
///
/// Input: an absolute path.
/// Output: a stable description of the file's current bytes (size + mtime),
/// or nil when the file cannot be read.
/// Purpose: the thumbnail cache can serve a cached decode only while the file
/// is unchanged; comparing identity avoids re-decoding untouched files.
/// Dependencies: `FileManager`.
struct ChatImageFileIdentity: Equatable {
    let path: String
    let size: Int64
    let modified: TimeInterval
}

/// Identity computation for image files (pure, disk-only).
enum ChatImageFileIdentityLogic {
    /// Current identity of the file at `path`, or nil when unreadable.
    static func identity(for path: String) -> ChatImageFileIdentity? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64,
              let modified = attrs[.modificationDate] as? Date else {
            return nil
        }
        return ChatImageFileIdentity(path: path, size: size, modified: modified.timeIntervalSince1970)
    }
}

/// Downscaling of an image to a maximum side (pure, no UI).
///
/// Input: an image and a maximum side in points.
/// Output: a new image whose larger dimension is at most `side` (aspect kept),
/// or the original when it already fits, or nil for an empty image.
/// Purpose: thumbnails are small (≤150 pt); decoding and storing the full image
/// would waste memory and stall rendering, so previews are scaled once.
/// Dependencies: `CGContext` (no AppKit drawing context needed — headless-safe).
enum ChatThumbnailScaler {
    static func scaled(image: NSImage, toMaximumSide side: CGFloat) -> NSImage? {
        let size = image.size
        guard size.width > 0, size.height > 0, side > 0 else { return nil }
        let maxDimension = max(size.width, size.height)
        guard maxDimension > side else { return image }
        let factor = side / maxDimension
        let targetWidth = max(1, Int((size.width * factor).rounded()))
        let targetHeight = max(1, Int((size.height * factor).rounded()))
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let ctx = CGContext(
                  data: nil,
                  width: targetWidth,
                  height: targetHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let output = (ctx.draw(source, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)),
                            ctx.makeImage()).1 else {
            return nil
        }
        return NSImage(cgImage: output, size: NSSize(width: targetWidth, height: targetHeight))
    }
}

/// Live counters of the thumbnail store (tests assert no repeated work).
struct ChatThumbnailStats {
    var hits = 0          // served from cache (fresh entry)
    var refreshes = 0     // served from cache after TTL, file unchanged
    var misses = 0        // no usable entry → load scheduled
    var loads = 0         // actual file loads
    var scalings = 0      // actual downscale calls
    var stores = 0        // entries inserted
    var evictions = 0     // LRU drops
    var emptyReturns = 0  // loader returned nil
}

/// Memoized, off-main, bounded thumbnail store for chat inline image previews.
///
/// Input: an absolute image path and a desired maximum side.
/// Output: a scaled thumbnail, loaded off the main thread.
/// Purpose: fixing the scroll stall — `NSImage(contentsOfFile:)` inside a row
/// body decoded full images on the main thread every time a lazy row
/// re-materialized. This store loads/scales once per unchanged file and
/// reuses the result while the row reappears.
/// Dependencies: `ChatImageFileIdentityLogic` (file identity), `ChatThumbnailScaler`.
final class ChatThumbnailCache {
    static let shared = ChatThumbnailCache()

    struct Key: Hashable {
        let path: String
        let side: CGFloat
    }

    private struct Entry {
        let image: NSImage
        let identity: ChatImageFileIdentity
        var createdAt: Date
    }

    /// Maximum cached entries before LRU eviction.
    var maxEntries = 128
    /// How long a cached entry is trusted without re-statting the file.
    var ttl: TimeInterval = 2.0
    /// Injectable clock (tests advance it to exercise TTL expiry).
    var now: () -> Date = { Date() }
    /// Injectable image loader — production reads from disk.
    var loader: (String) -> NSImage? = { NSImage(contentsOfFile: $0) }
    /// Injectable scaler — production uses `ChatThumbnailScaler`.
    var scaler: (NSImage, CGFloat) -> NSImage? = {
        ChatThumbnailScaler.scaled(image: $0, toMaximumSide: $1)
    }

    private(set) var stats = ChatThumbnailStats()

    /// Identity wrapper so in-flight loads can be compared by reference and
    /// removed by the awaiter that owns them (Task itself is a value type).
    private final class PendingLoad {
        let task: Task<NSImage?, Never>
        init(_ task: Task<NSImage?, Never>) { self.task = task }
    }

    private var cache: [Key: Entry] = [:]
    private var order: [Key] = []
    private var inFlight: [Key: PendingLoad] = [:]
    private let lock = NSLock()

    /// Internal so tests can create isolated instances; production uses `shared`.
    init() {}

    /// Synchronous peek: cached image for the path/side if a fresh entry
    /// exists. Never loads. Used by tests and by the async path as a fast
    /// first hit.
    func cachedThumbnail(for path: String, side: CGFloat) -> NSImage? {
        let key = Key(path: path, side: side)
        lock.lock()
        defer { lock.unlock() }
        guard var entry = cache[key] else {
            stats.misses += 1
            return nil
        }
        let age = now().timeIntervalSince(entry.createdAt)
        if age <= ttl {
            stats.hits += 1
            return entry.image
        }
        // Expired: refresh without reloading when the file is unchanged.
        guard let identity = ChatImageFileIdentityLogic.identity(for: path),
              identity == entry.identity else {
            stats.misses += 1
            return nil
        }
        entry.createdAt = now()
        cache[key] = entry
        stats.refreshes += 1
        return entry.image
    }

    /// Async load (off-main) + cache. Deduplicates concurrent requests for the
    /// same key so one fast scroll does not decode the same file several times.
    func thumbnail(for path: String, side: CGFloat) async -> NSImage? {
        let key = Key(path: path, side: side)
        if let hit = cachedThumbnail(for: path, side: side) {
            return hit
        }
        lock.lock()
        if let existing = inFlight[key] {
            lock.unlock()
            return await existing.task.value
        }
        let task: Task<NSImage?, Never> = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return nil }
            guard let loaded = loader(path) else {
                lock.lock()
                stats.emptyReturns += 1
                lock.unlock()
                return nil
            }
            lock.lock()
            stats.scalings += 1
            lock.unlock()
            return scaler(loaded, side)
        }
        let pending = PendingLoad(task)
        inFlight[key] = pending
        lock.unlock()

        let image = await task.value
        lock.lock()
        if inFlight[key] === pending {
            inFlight.removeValue(forKey: key)
        }
        lock.unlock()
        if let image {
            store(image: image, key: key)
        }
        return image
    }

    /// Insert a decoded thumbnail, evicting the oldest entry past `maxEntries`.
    private func store(image: NSImage, key: Key) {
        lock.lock()
        defer { lock.unlock() }
        guard let identity = ChatImageFileIdentityLogic.identity(for: key.path),
              cache[key] == nil else { return }
        cache[key] = Entry(image: image, identity: identity, createdAt: now())
        order.append(key)
        stats.stores += 1
        while cache.count > maxEntries, order.count > 1 {
            let victim = order.removeFirst()
            if cache.removeValue(forKey: victim) != nil {
                stats.evictions += 1
            }
        }
    }

    /// Clear state (tests).
    func resetForTesting() {
        lock.lock()
        cache.removeAll()
        order.removeAll()
        inFlight.removeAll()
        stats = ChatThumbnailStats()
        lock.unlock()
    }
}
