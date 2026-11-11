import Foundation
import Testing
@testable import myCoder

@MainActor
@Suite("Engine discovery never launches the engine")
struct EngineLocatorTests {
    private func fixture(version: String?) throws -> (root: URL, app: URL, marker: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("engine-locator-\(UUID().uuidString)")
        let app = root.appendingPathComponent("Chromium.app")
        let binary = app.appendingPathComponent("Contents/MacOS/Chromium")
        try FileManager.default.createDirectory(at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
        let marker = root.appendingPathComponent("unexpected-launch")
        // This is a local test executable, not Chromium. Discovery must never run it.
        let script = "#!/bin/sh\ntouch '\(marker.path)'\nprintf 'Chrome/999.0\\n'\n"
        try script.write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
        if let version {
            let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleShortVersionString": version], format: .xml, options: 0)
            try plist.write(to: app.appendingPathComponent("Contents/Info.plist"))
        }
        return (root, app, marker)
    }

    @Test func readsBundleVersionWithoutLaunchingExecutable() throws {
        let f = try fixture(version: "156.0.8078.48")
        defer { try? FileManager.default.removeItem(at: f.root) }
        let info = EngineLocator.verify(f.app)
        #expect(info?.version == "156.0.8078.48")
        #expect(info?.isVerified == true)
        #expect(!FileManager.default.fileExists(atPath: f.marker.path))
    }

    @Test func missingMetadataDoesNotFallBackToExecutingBinary() throws {
        let f = try fixture(version: nil)
        defer { try? FileManager.default.removeItem(at: f.root) }
        let info = EngineLocator.verify(f.app)
        #expect(info?.isVerified == false)
        #expect(!FileManager.default.fileExists(atPath: f.marker.path))
    }

    @Test func missingExecutableIsNotAnEngine() throws {
        let f = try fixture(version: "156.0")
        defer { try? FileManager.default.removeItem(at: f.root) }
        try FileManager.default.removeItem(at: f.app.appendingPathComponent("Contents/MacOS/Chromium"))
        #expect(EngineLocator.verify(f.app) == nil)
    }
}
