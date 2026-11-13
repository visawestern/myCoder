import AppKit
import Foundation
import Testing
@testable import myCoder

/// TDD for the scroll-stall fix: decoded message attachments (base64) are
/// memoized so a row that re-materializes while scrolling does not decode the
/// same payload again on the main thread.
@Suite("Base64 image decode cache — memoized, bounded")
struct ChatBase64ImageCacheTests {

    @Test("Same payload decodes once")
    func memoizesDecode() {
        let cache = ChatBase64ImageCache()
        var decodes = 0
        cache.decode = { payload in
            decodes += 1
            return self.makeImage()
        }
        let payload = "aGVsbG8="
        let first = cache.image(forBase64: payload)
        let second = cache.image(forBase64: payload)
        #expect(first != nil)
        #expect(second != nil)
        #expect(decodes == 1)
        #expect(cache.stats.hits >= 1)
    }

    @Test("Invalid payload returns nil and is not cached")
    func invalidPayloadNotCached() {
        let cache = ChatBase64ImageCache()
        var decodes = 0
        cache.decode = { _ in decodes += 1; return nil }
        let payload = "!!!not-base64!!!"
        #expect(cache.image(forBase64: payload) == nil)
        #expect(cache.image(forBase64: payload) == nil)
        #expect(decodes == 2, "nil не кэшируется — каждый вызов декодирует снова")
    }

    @Test("LRU eviction drops the oldest payload")
    func lruEvictsOldest() {
        let cache = ChatBase64ImageCache()
        cache.maxEntries = 4
        cache.decode = { _ in self.makeImage() }
        for index in 0..<5 {
            _ = cache.image(forBase64: "payload-\(index)")
        }
        _ = cache.image(forBase64: "payload-0")
        #expect(cache.stats.evictions >= 1)
    }

    @Test("Reset clears cache and counters")
    func resetClears() {
        let cache = ChatBase64ImageCache()
        cache.decode = { _ in self.makeImage() }
        _ = cache.image(forBase64: "x")
        cache.resetForTesting()
        var decodes = 0
        cache.decode = { _ in decodes += 1; return self.makeImage() }
        _ = cache.image(forBase64: "x")
        #expect(decodes == 1)
    }

    private func makeImage() -> NSImage {
        guard let ctx = CGContext(
            data: nil,
            width: 8,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 32,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return NSImage() }
        ctx.setFillColor(NSColor.systemBlue.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        guard let cg = ctx.makeImage() else { return NSImage() }
        return NSImage(cgImage: cg, size: NSSize(width: 8, height: 8))
    }
}
