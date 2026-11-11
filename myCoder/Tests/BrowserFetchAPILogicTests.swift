import Foundation
import Testing
@testable import myCoder

@MainActor
@Suite("browser.fetch internal API")
struct BrowserFetchAPILogicTests {
    @Test func scalarArgumentsNormalizeToRealToolContract() throws {
        let arguments = try BrowserFetchAPILogic.arguments(from: [
            "target_url": "https://example.com", "css_selector": "main",
            "screenshot": true, "max_chars": 200
        ])
        #expect(arguments["url"] == "https://example.com")
        #expect(arguments["selector"] == "main")
        #expect(arguments["screenshot"] == "true")
        #expect(arguments["limit"] == "200")
    }

    @Test func invalidRequestsAreRejectedBeforeExecutorRuns() async {
        let requests: [[String: Any]] = [
            [:], ["url": ""], ["url": "file:///tmp/private"],
            ["url": "https://example.com", "script": ["unexpected": "object"]],
            ["url": "https://example.com", "selector": ["unexpected"]],
            ["url": "https://example.com", "limit": 1.5],
            ["url": "https://example.com", "selector": "main", "script": "document.title"]
        ]
        for request in requests {
            var executed = false
            do {
                _ = try await BrowserFetchAPILogic.perform(params: request) { _ in
                    executed = true
                    return "must not execute"
                }
                Issue.record("Invalid request accepted")
            } catch {
                #expect(error is AppActionError)
            }
            #expect(!executed)
        }
    }

    @Test func dispatcherFailureRemainsVisibleInJSON() {
        let output = "error: browser_fetch requires an active browser session"
        let result = BrowserFetchAPILogic.result(output: output)
        #expect(result["ok"] as? Bool == false)
        #expect(result["output"] as? String == output)
        #expect(result["screenshot"] as? Bool == false)
    }

    @Test func resultPreservesTextAndActualPNGMarker() throws {
        let png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aO1sAAAAASUVORK5CYII="
        let output = "Clicked\nATTACHED_IMAGE:image/png:\(png)"
        let result = BrowserFetchAPILogic.result(output: output)
        #expect(result["ok"] as? Bool == true)
        #expect(result["output"] as? String == output)
        #expect(result["screenshot"] as? Bool == true)
        #expect(result["screenshotBytes"] as? Int == Data(base64Encoded: png)?.count)
        #expect(BrowserFetchAPILogic.result(output: "text\nATTACHED_IMAGE:image/png:invalid")["screenshot"] as? Bool == false)
    }

    @Test @MainActor func catalogDescribesBrowserAction() throws {
        let row = try #require(AppActionRouter.catalog.first { $0["name"] as? String == "browser.fetch" })
        let params = try #require(row["params"] as? [[String: Any]])
        let url = try #require(params.first { $0["name"] as? String == "url" })
        #expect(url["required"] as? Bool == true)
        #expect(Set(params.compactMap { $0["name"] as? String }) == ["url", "selector", "script", "click", "screenshot", "limit"])
    }

    @Test @MainActor func invalidActionDoesNotTouchEngineOrTabs() async {
        let state = AppState()
        let phase = EngineStatusCenter.shared.phase
        let tabs = AntiBrowserTabManager.shared.allBridges().map(\.key)
        do {
            _ = try await AppActionRouter.shared.perform(action: "browser.fetch", params: ["url": "file:///tmp/private"], appState: state)
            Issue.record("Invalid URL should be rejected")
        } catch AppActionError.invalidParameter { }
        catch { Issue.record("Wrong rejection: \(error.localizedDescription)") }
        #expect(EngineStatusCenter.shared.phase == phase)
        #expect(AntiBrowserTabManager.shared.allBridges().map(\.key) == tabs)
    }
}
