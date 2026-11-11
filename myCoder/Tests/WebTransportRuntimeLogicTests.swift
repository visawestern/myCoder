import Testing
@testable import myCoder

@MainActor
@Suite("WEB-05 browser transport honesty")
struct WebTransportRuntimeLogicTests {
    @Test("the only transport is AntiBrowser (CDP + REST)")
    func managedTransportLabel() {
        #expect(WebTransportRuntimeLogic.label(for: .playwrightMCP) == "AntiBrowser (CDP + REST)")
        #expect(WebTransportRuntimeLogic.effectiveTransport(for: .playwrightMCP) == .cdpCookies)
        #expect(WebTransportRuntimeLogic.effectiveTransport(for: .cdpCookies) == .cdpCookies)
    }

    @Test("connection summary names the AntiBrowser runtime")
    func connectionSummaryUsesRuntimeLabel() {
        let config = WebProviderConfig(
            id: "anti",
            vendor: .kimi,
            transport: .cdpCookies,
            selectedModel: "model"
        )
        let summary = WebProviderConnectivity.connectionSummary(config, connected: true)
        #expect(summary.hasPrefix("AntiBrowser (CDP + REST)"))
    }
}
