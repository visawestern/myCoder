import AppKit
import Foundation
import Testing
@testable import myCoder

/// TDD for the scroll-stall fix: inline file thumbnails must be loaded and
/// scaled OFF the main thread and memoized, so scrolling through chat rows
/// does not re-decode full images on every materialization.
@Suite("Chat thumbnail cache — off-main, memoized, bounded")
struct ChatThumbnailCacheTests {

    // MARK: - Scalers

    @Test("Scaler keeps aspect ratio when scaling down")
    func scalerKeepsAspect() throws {
        let image = Self.makeImage(width: 400, height: 200)
        let scaled = ChatThumbnailScaler.scaled(image: image, toMaximumSide: 150)
        let result = try #require(scaled)
        #expect(result.size.width <= 150)
        #expect(result.size.height <= 150)
        // 400:200 = 2:1 → 150:75 (rounding tolerance ±1)
        #expect(abs(result.size.width - 150) <= 1)
        #expect(abs(result.size.height - 75) <= 1)
    }

    @Test("Scaler never upscales small images")
    func scalerDoesNotUpscale() throws {
        let image = Self.makeImage(width: 50, height: 30)
        let scaled = ChatThumbnailScaler.scaled(image: image, toMaximumSide: 150)
        let result = try #require(scaled)
        #expect(result.size == NSSize(width: 50, height: 30))
    }

    @Test("Scaler returns nil for empty image")
    func scalerEmptyImage() {
        let empty = NSImage(size: NSSize(width: 0, height: 0))
        #expect(ChatThumbnailScaler.scaled(image: empty, toMaximumSide: 150) == nil)
    }

    // MARK: - Store

    @Test("First request loads once, second request hits cache")
    func firstLoadsThenCaches() async throws {
        let store = ChatThumbnailCache()
        var loads = 0
        store.loader = { _ in
            loads += 1
            return Self.makeImage(width: 60, height: 40)
        }
        store.scaler = { image, _ in image }
        let file = try makeTempImageFile()
        defer { try? FileManager.default.removeItem(at: file) }

        let first = await store.thumbnail(for: file.path, side: 150)
        #expect(first != nil)
        #expect(loads == 1)

        let second = await store.thumbnail(for: file.path, side: 150)
        #expect(second != nil)
        #expect(loads == 1, "повторный запрос не должен декодировать снова")
        #expect(store.stats.hits >= 1)
    }

    @Test("Concurrent requests for the same path share one load")
    func concurrentRequestsShareOneLoad() async throws {
        let store = ChatThumbnailCache()
        var loads = 0
        store.loader = { _ in
            loads += 1
            return Self.makeImage(width: 60, height: 40)
        }
        store.scaler = { image, _ in image }
        let file = try makeTempImageFile()
        defer { try? FileManager.default.removeItem(at: file) }

        async let first = store.thumbnail(for: file.path, side: 150)
        async let second = store.thumbnail(for: file.path, side: 150)
        let a = await first
        let b = await second
        #expect(a != nil)
        #expect(b != nil)
        #expect(loads == 1)
    }

    @Test("Missing file returns nil without crashing")
    func missingFileReturnsNil() async {
        let store = ChatThumbnailCache()
        var loads = 0
        store.loader = { _ in loads += 1; return nil }
        let image = await store.thumbnail(for: "/nonexistent/path.png", side: 150)
        #expect(image == nil)
        #expect(loads == 1)
    }

    @Test("Same file after TTL refreshes without reloading")
    func ttlRefreshKeepsDecode() async throws {
        let store = ChatThumbnailCache()
        store.ttl = 2
        var now = Date()
        store.now = { now }
        var loads = 0
        store.loader = { _ in loads += 1; return Self.makeImage(width: 20, height: 20) }
        store.scaler = { image, _ in image }
        let file = try makeTempImageFile()
        defer { try? FileManager.default.removeItem(at: file) }

        _ = await store.thumbnail(for: file.path, side: 150)
        #expect(loads == 1)

        now = now.addingTimeInterval(10) // TTL истёк, файл не менялся
        let again = await store.thumbnail(for: file.path, side: 150)
        #expect(again != nil)
        #expect(loads == 1, "неизменный файл не должен декодироваться повторно")
        #expect(store.stats.refreshes >= 1)
    }

    @Test("Changed file after TTL is reloaded")
    func ttlChangedFileReloads() async throws {
        let store = ChatThumbnailCache()
        store.ttl = 2
        var now = Date()
        store.now = { now }
        var loads = 0
        store.loader = { _ in loads += 1; return Self.makeImage(width: 20, height: 20) }
        store.scaler = { image, _ in image }
        let file = try makeTempImageFile()
        defer { try? FileManager.default.removeItem(at: file) }

        _ = await store.thumbnail(for: file.path, side: 150)
        #expect(loads == 1)

        try Data("different-size".utf8).write(to: file) // размер/содержимое изменились
        now = now.addingTimeInterval(10)
        _ = await store.thumbnail(for: file.path, side: 150)
        #expect(loads == 2, "изменённый файл должен декодироваться заново")
    }

    @Test("LRU eviction drops the oldest entry")
    func lruEvictsOldest() async throws {
        let store = ChatThumbnailCache()
        store.maxEntries = 4
        var loads = 0
        store.loader = { _ in loads += 1; return Self.makeImage(width: 10, height: 10) }
        store.scaler = { image, _ in image }

        var files: [URL] = []
        defer { for file in files { try? FileManager.default.removeItem(at: file) } }
        for index in 0..<5 {
            let file = try makeTempImageFile()
            files.append(file)
            _ = await store.thumbnail(for: file.path, side: 150)
        }
        #expect(loads == 5)

        // Самая старая запись вытеснена → повторный запрос снова декодирует.
        _ = await store.thumbnail(for: files[0].path, side: 150)
        #expect(loads == 6)
        #expect(store.stats.evictions >= 1)
    }

    // MARK: - Helpers

    private func makeTempImageFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("thumb-\(UUID().uuidString).png")
        try Data("fake-image-bytes".utf8).write(to: url)
        return url
    }

    private static func makeImage(width: Int, height: Int) -> NSImage {
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return NSImage() }
        ctx.setFillColor(NSColor.systemBlue.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let cg = ctx.makeImage() else { return NSImage() }
        return NSImage(cgImage: cg, size: NSSize(width: width, height: height))
    }
}
