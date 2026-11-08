import AppKit
import Foundation

/// The app's own screenshots: captured from the window's view tree
/// (`AppWindowCapture`) and saved into `~/myCoderScreenshots`.
///
/// This is the single code path shared by BOTH the «Скриншоты» menu item and
/// the HTTP action `ui.screenshot` — there is no API-only capture that a user
/// could not also do from the interface.
@MainActor
struct ScreenshotsStore {
    struct ShotInfo: Codable, Equatable, Sendable {
        var path: String
        var width: Int
        var height: Int
        var method: String
        var windowTitle: String
        var bytes: Int

        var dictionary: [String: Any] {
            [
                "path": path,
                "width": width,
                "height": height,
                "method": method,
                "windowTitle": windowTitle,
                "bytes": bytes
            ]
        }
    }

    enum Error: LocalizedError {
        case captureFailed

        var errorDescription: String? {
            switch self {
            case .captureFailed: return "No visible window content to capture"
            }
        }
    }

    static func directory(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory.appendingPathComponent("myCoderScreenshots", isDirectory: true)
    }

    /// Capture the front app window and save it into the screenshots folder.
    /// Returns the saved shot's metadata.
    @discardableResult
    static func captureAndSave(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> ShotInfo {
        guard let shot = AppWindowCapture.capture() else {
            throw Error.captureFailed
        }
        let dir = directory(homeDirectory: homeDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = isoStamp()
        let url = dir.appendingPathComponent("shot-\(stamp).png")
        try AppWindowCapture.write(shot, to: url)
        return ShotInfo(
            path: url.path,
            width: shot.width,
            height: shot.height,
            method: shot.method,
            windowTitle: shot.windowTitle,
            bytes: shot.pngData.count
        )
    }

    /// The saved screenshots, newest first.
    static func list(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [ShotInfo] {
        let dir = directory(homeDirectory: homeDirectory)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return [] }
        return urls
            .filter { $0.pathExtension.lowercased() == "png" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .compactMap { url in
                guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else {
                    return nil
                }
                let stamp = values.contentModificationDate.map { isoStamp(from: $0) } ?? ""
                return ShotInfo(
                    path: url.path,
                    width: 0,
                    height: 0,
                    method: "saved",
                    windowTitle: stamp,
                    bytes: values.fileSize ?? 0
                )
            }
    }

    /// Open the screenshots folder in Finder.
    static func reveal(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        let dir = directory(homeDirectory: homeDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    private static func isoStamp(from date: Date = Date()) -> String {
        ISO8601DateFormatter().string(from: date).replacingOccurrences(of: ":", with: "-")
    }
}
