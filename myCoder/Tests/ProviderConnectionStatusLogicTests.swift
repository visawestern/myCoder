import Testing
@testable import myCoder

@Suite("Selected provider connection status")
struct ProviderConnectionStatusLogicTests {
    @Test("Serve connectivity cannot masquerade as an unavailable Auto Free provider")
    func serverDoesNotMaskAutoFree() {
        #expect(!ProviderConnectionStatusLogic.isConnected(
            selectedID: "mycoder-auto-free",
            serverProviderIDs: ["serve-provider"],
            serverConnected: true,
            autoFreeID: "mycoder-auto-free",
            autoFreeReady: false,
            webConnected: nil,
            localEnabled: false,
            customReady: false,
            remembered: nil
        ))
    }

    @Test("Serve connectivity cannot masquerade as an expired web login")
    func serverDoesNotMaskWeb() {
        #expect(!ProviderConnectionStatusLogic.isConnected(
            selectedID: "web:chatgpt",
            serverProviderIDs: ["serve-provider"],
            serverConnected: true,
            autoFreeID: "mycoder-auto-free",
            autoFreeReady: true,
            webConnected: false,
            localEnabled: false,
            customReady: false,
            remembered: nil
        ))
    }

    @Test("ready direct providers report connected without Serve")
    func directProvidersCanBeConnected() {
        #expect(ProviderConnectionStatusLogic.isConnected(
            selectedID: "mycoder-auto-free",
            serverProviderIDs: [],
            serverConnected: false,
            autoFreeID: "mycoder-auto-free",
            autoFreeReady: true,
            webConnected: nil,
            localEnabled: false,
            customReady: false,
            remembered: nil
        ))
        #expect(ProviderConnectionStatusLogic.isConnected(
            selectedID: "local-ollama",
            serverProviderIDs: [],
            serverConnected: false,
            autoFreeID: "mycoder-auto-free",
            autoFreeReady: true,
            webConnected: nil,
            localEnabled: true,
            customReady: false,
            remembered: nil
        ))
    }

    @Test("endpoint label follows selected route instead of global Serve state")
    func endpointLabelFollowsRoute() {
        #expect(ProviderConnectionStatusLogic.endpointLabel(
            selectedID: "web:chatgpt",
            serverProviderIDs: ["serve-provider"],
            serverConnected: true,
            serverHost: "127.0.0.1",
            serverPort: 1234
        ) == "web:chatgpt")
        #expect(ProviderConnectionStatusLogic.endpointLabel(
            selectedID: "serve-provider",
            serverProviderIDs: ["serve-provider"],
            serverConnected: true,
            serverHost: "127.0.0.1",
            serverPort: 1234
        ) == "127.0.0.1:1234")
    }

    @Test("empty or invalid Serve endpoint data fails closed to the selected provider label")
    func endpointLabelRejectsInvalidServerData() {
        #expect(ProviderConnectionStatusLogic.endpointLabel(
            selectedID: "",
            serverProviderIDs: [""],
            serverConnected: true,
            serverHost: "127.0.0.1",
            serverPort: 1234
        ) == "")
        #expect(ProviderConnectionStatusLogic.endpointLabel(
            selectedID: "serve-provider",
            serverProviderIDs: ["serve-provider"],
            serverConnected: true,
            serverHost: "",
            serverPort: 0
        ) == "serve-provider")
    }
}
