import Foundation
import Testing
@testable import myCoder

@Suite("SET-05 MCP config mutation safety")
struct MCPConfigMutationLogicTests {
    private let source = """
    {"mcpServers":{"alpha":{"url":"https://alpha.test"},"beta":{"command":"beta"}}}
    """

    @Test("disabling one server preserves other configured servers")
    func setDisabledPreservesSiblings() throws {
        let output = try MCPConfigMutationLogic.setDisabled(
            data: Data(source.utf8), id: "alpha", disabled: true
        )
        let root = try #require(JSONSerialization.jsonObject(with: output) as? [String: Any])
        let servers = try #require(root["mcpServers"] as? [String: Any])
        let alpha = try #require(servers["alpha"] as? [String: Any])
        #expect(alpha["disabled"] as? Bool == true)
        #expect(servers["beta"] != nil)
    }

    @Test("missing MCP target is a failure, not a silent success")
    func missingTargetFails() {
        #expect(throws: MCPConfigMutationError.self) {
            try MCPConfigMutationLogic.setDisabled(
                data: Data(source.utf8), id: "missing", disabled: true
            )
        }
    }

    @Test("removing one server preserves all remaining servers")
    func removePreservesSiblings() throws {
        let output = try MCPConfigMutationLogic.remove(data: Data(source.utf8), id: "alpha")
        let root = try #require(JSONSerialization.jsonObject(with: output) as? [String: Any])
        let servers = try #require(root["mcpServers"] as? [String: Any])
        #expect(servers["alpha"] == nil)
        #expect(servers["beta"] != nil)
    }
}
