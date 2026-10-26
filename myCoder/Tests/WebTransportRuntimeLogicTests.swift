import Testing
@testable import myCoder

@Suite("WEB-05 browser transport honesty")
struct WebTransportRuntimeLogicTests {
    @Test("managed transport is labeled as in-app WKWebView")
    func managedTransportLabel() {
        #expect(WebTransportRuntimeLogic.label(for: .playwrightMCP) == "In-app WKWebView")
        #expect(WebTransportRuntimeLogic.effectiveTransport(for: .playwrightMCP) == .playwrightMCP)
    }

    @Test("legacy CDP choice cannot claim Chrome is actually attached")
    func legacyCDPIsHonest() {
        #expect(WebTransportRuntimeLogic.label(for: .cdpCookies).contains("WKWebView"))
        #expect(WebTransportRuntimeLogic.label(for: .cdpCookies).contains("unavailable"))
        #expect(WebTransportRuntimeLogic.effectiveTransport(for: .cdpCookies) == .playwrightMCP)
    }

    @Test("connection summary uses the honest runtime label")
    func connectionSummaryUsesRuntimeLabel() {
        let config = WebProviderConfig(
            id: "legacy-cdp",
            vendor: .kimi,
            transport: .cdpCookies,
            selectedModel: "model"
        )
        let summary = WebProviderConnectivity.connectionSummary(config, connected: true)
        #expect(summary.hasPrefix("In-app WKWebView (Chrome CDP unavailable)"))
    }
}
