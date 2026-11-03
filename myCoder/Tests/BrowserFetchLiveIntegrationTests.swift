import Foundation
import AppKit
import Testing
@testable import myCoder

/// Opt-in test against the engine ALREADY started by myCoder. This test must
/// never bootstrap an engine from the test process or modify the shared profile.
///
/// Fixture contract at MYCODER_BROWSER_FIXTURE_URL:
///   <title>BrowserFetchFixture</title>
///   <main id="payload">Browser fetch live fixture</main>
///   <button id="activate" onclick="document.querySelector('#status').textContent='Clicked'">Click</button>
///   <p id="status">Ready</p>
@Suite("browser_fetch live integration")
@MainActor
struct BrowserFetchLiveIntegrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MYCODER_LIVE_BROWSER"] == "1"))
    func textScriptClickAndScreenshotUseLiveEngine() async throws {
        let environment = ProcessInfo.processInfo.environment
        let fixture = try #require(environment["MYCODER_BROWSER_FIXTURE_URL"],
                                   "Set MYCODER_BROWSER_FIXTURE_URL to the HTTP fixture described above")
        let fixtureURL = try #require(URL(string: fixture))
        try #require(["http", "https"].contains(fixtureURL.scheme?.lowercased() ?? ""))

        // A failed precondition ends the test, rather than launching Chromium.
        let versionURL = try #require(URL(string: "http://127.0.0.1:5390/version"))
        var versionRequest = URLRequest(url: versionURL)
        versionRequest.timeoutInterval = 5
        let (_, versionResponse) = try await URLSession.shared.data(for: versionRequest)
        try #require((versionResponse as? HTTPURLResponse)?.statusCode == 200,
                     "Start the engine through myCoder before enabling this test")

        let profile = BrowserProcess.Config.defaultProfileDir
        let state = try Data(contentsOf: profile.appendingPathComponent("Local State"))
        let decodedState = try JSONSerialization.jsonObject(with: state)
        let object = try #require(decodedState as? [String: Any])
        let antibrowser = try #require(object["antibrowser"] as? [String: Any])
        let api = try #require(antibrowser["agent_api"] as? [String: Any])
        let token = try #require(api["token"] as? String)
        try #require(!token.isEmpty)

        let tabKey = "browser-fetch-live|test|\(UUID().uuidString)"
        let bridge = AntiBrowserAutomationBridge(tabKey: tabKey, apiPort: 5390, profileDir: profile)
        bridge.engineBootstrap = nil // no real or fake bootstrap, even on a later REST failure
        var executor = ProjectWebToolExecutor(projectRoot: FileManager.default.temporaryDirectory.path)
        executor.bridge = bridge

        func closeOwnTab() async throws {
            let url = try #require(URL(string: "http://127.0.0.1:5390/tabs/close"))
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 10
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(token, forHTTPHeaderField: "X-AntiBrowser-Token")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["tab_key": tabKey])
            let (data, response) = try await URLSession.shared.data(for: request)
            try #require((response as? HTTPURLResponse)?.statusCode == 200)
            let decodedResponse = try JSONSerialization.jsonObject(with: data)
            let json = try #require(decodedResponse as? [String: Any])
            try #require(json["ok"] as? Bool == true)
        }

        do {
            let text = await executor.execute(WebToolCall(name: "browser_fetch", arguments: [
                "url": fixture, "selector": "#payload", "limit": "2000"
            ]))
            try #require(!text.hasPrefix("error:"), "Live text retrieval failed")
            #expect(text.contains("Browser fetch live fixture"))

            let script = await executor.execute(WebToolCall(name: "browser_fetch", arguments: [
                "url": fixture, "script": "document.title"
            ]))
            try #require(!script.hasPrefix("error:"), "Live JS retrieval failed")
            #expect(script.contains("--- JS result ---"))
            #expect(script.contains("BrowserFetchFixture"))

            let clicked = await executor.execute(WebToolCall(name: "browser_fetch", arguments: [
                "url": fixture, "click": "#activate", "selector": "#status",
                "screenshot": "true", "limit": "2000"
            ]))
            try #require(!clicked.hasPrefix("error:"), "Live click/screenshot failed")
            #expect(clicked.contains("Clicked"))
            let marker = "ATTACHED_IMAGE:image/png:"
            let range = try #require(clicked.range(of: marker), "Screenshot must be returned by the real engine")
            let base64 = String(clicked[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let png = try #require(Data(base64Encoded: base64))
            #expect(Array(png.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10])
            let image = try #require(NSBitmapImageRep(data: png), "Engine screenshot must decode as an image")
            #expect(image.pixelsWide > 0)
            #expect(image.pixelsHigh > 0)
            try await closeOwnTab()
        } catch {
            try? await closeOwnTab()
            throw error
        }
    }
}
