import Testing
import Foundation
@testable import myCoder

@Suite("Message Send Options")
struct MessageSendOptionsTests {

    @Test("Agent mode maps to build plan compose API values")
    func agentModeMapping() {
        #expect(SessionSendLogic.sendMode(for: .build) == "build")
        #expect(SessionSendLogic.sendMode(for: .plan) == "plan")
        #expect(SessionSendLogic.sendMode(for: .compose) == "compose")
    }

    @Test("Send options encode nested model agent variant and messageID")
    func bodyEncoding() throws {
        let options = MessageSendOptions(
            agent: "plan",
            modelID: "mycoder-auto-free",
            providerID: "mimo",
            variant: "high",
            messageID: "msg_001"
        )
        let body = options.requestBody(parts: [["type": "text", "text": "hello"]])
        #expect(body["agent"] as? String == "plan")
        #expect(body["mode"] == nil)
        let model = body["model"] as? [String: Any]
        #expect(model?["modelID"] as? String == "mycoder-auto-free")
        #expect(model?["providerID"] as? String == "mimo")
        #expect(body["variant"] as? String == "high")
        #expect(body["messageID"] as? String == "msg_001")
    }

    @Test("Send options omit variant when nil")
    func bodyOmitsNilVariant() {
        let options = MessageSendOptions(
            agent: "build",
            modelID: "gpt-4o",
            providerID: "openai",
            variant: nil,
            messageID: nil
        )
        let body = options.requestBody(parts: [])
        #expect(body["variant"] == nil)
        #expect(body["messageID"] == nil)
    }

    @Test("Build send options from app selections")
    func buildFromSelections() {
        let providers = sampleProviders()
        let options = SessionSendLogic.buildSendOptions(
            agentMode: .compose,
            selectedVariant: "medium",
            modelID: "mycoder-auto-free",
            selectedProviderID: "mimo",
            providers: providers,
            customProviders: [],
            messageID: "msg_test"
        )
        #expect(options.agent == "compose")
        #expect(options.modelID == "mycoder-auto-free")
        #expect(options.providerID == "mimo")
        #expect(options.variant == "medium")
        #expect(options.messageID == "msg_test")
    }

    private func sampleProviders() -> [MimoProviderResponse] {
        [
            MimoProviderResponse(
                id: "mimo",
                name: "MiMo",
                models: [
                    "mycoder-auto-free": MimoProviderModel(
                        id: "mycoder-auto-free",
                        name: "myCoder Auto Free",
                        status: "active",
                        providerID: "mimo",
                        capabilities: MimoModelCapabilities(reasoning: true),
                        variants: [
                            "low": MimoModelVariant(reasoningEffort: "low"),
                            "medium": MimoModelVariant(reasoningEffort: "medium"),
                            "high": MimoModelVariant(reasoningEffort: "high")
                        ]
                    )
                ]
            )
        ]
    }
}

@Suite("Message Parts Builder")
struct MessagePartsBuilderTests {

    @Test("Builds text image and file parts")
    func buildsAllPartTypes() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("hello.swift")
        try "print(\"hi\")".write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let parts = MessagePartsBuilder.build(
            text: "review this",
            files: [FileInfo(name: "hello.swift", type: .swift, path: tempURL.path)],
            images: [ClipboardImage(base64: "abc123", mimeType: "image/png")]
        )

        #expect(parts.count == 3)
        #expect(parts[0]["type"] as? String == "text")
        #expect(parts[1]["type"] as? String == "file")
        #expect(parts[1]["mime"] as? String == "image/png")
        #expect(parts[1]["url"] as? String == "data:image/png;base64,abc123")
        #expect(parts[2]["type"] as? String == "file")
        #expect(parts[2]["filename"] as? String == "hello.swift")
        #expect((parts[2]["url"] as? String)?.hasPrefix("file://") == true)
        #expect(parts[2]["mime"] as? String == "text/x-swift")
    }

    @Test("Image part uses MiMo Serve file+url contract")
    func imagePartContract() {
        let part = MessagePartsBuilder.imagePart(for: ClipboardImage(base64: "abc", mimeType: "image/png"))
        #expect(part?["type"] as? String == "file")
        #expect(part?["mime"] as? String == "image/png")
        #expect(part?["url"] as? String == "data:image/png;base64,abc")
    }

    @Test("Parses data URL back to base64")
    func dataURLRoundTrip() {
        let decoded = MessagePartsBuilder.base64FromDataURL("data:image/png;base64,abc123")
        #expect(decoded?.mimeType == "image/png")
        #expect(decoded?.base64 == "abc123")
    }

    @Test("Uses empty text part when nothing provided")
    func emptyFallback() {
        let parts = MessagePartsBuilder.build(text: "", files: [], images: [])
        #expect(parts.count == 1)
        #expect(parts[0]["text"] as? String == "")
    }
}

@Suite("Permission Mapping")
struct PermissionMappingTests {

    @Test("Access level maps to permission patch")
    func permissionPatch() {
        let ask = AccessLevelPermissionLogic.permissionPatch(for: .askBeforeChanges)
        #expect(ask["edit"] as? String == "ask")
        let auto = AccessLevelPermissionLogic.permissionPatch(for: .editAutomatically)
        #expect(auto["edit"] as? String == "allow")
        let full = AccessLevelPermissionLogic.permissionPatch(for: .fullAccess)
        #expect(full["edit"] as? String == "allow")
        #expect(full["bash"] as? String == "allow")
    }

    @Test("Permission patch maps back to access level")
    func reverseMapping() {
        #expect(AccessLevelPermissionLogic.accessLevel(from: ["edit": "ask"]) == .askBeforeChanges)
        #expect(AccessLevelPermissionLogic.accessLevel(from: ["edit": "allow"]) == .editAutomatically)
        #expect(AccessLevelPermissionLogic.accessLevel(from: ["edit": "allow", "bash": "allow"]) == .fullAccess)
    }

    @Test("Legacy plan mode migrates to ask before changes")
    func legacyPlanMode() {
        #expect(AccessLevelPermissionLogic.migrateLegacyAccessLevel(raw: "Plan mode") == .askBeforeChanges)
        #expect(AccessLevelPermissionLogic.shouldSwitchToPlanAgent(legacyRaw: "Plan mode"))
    }
}

@Suite("Provider Settings Logic")
struct ProviderSettingsLogicTests {

    @Test("Resolves provider ID for model")
    func providerForModel() {
        let providers = sampleProviders()
        #expect(ProviderSettingsLogic.providerID(for: "mycoder-auto-free", in: providers) == "mimo")
        #expect(ProviderSettingsLogic.providerID(for: "missing", in: providers) == nil)
    }

    @Test("Available variants come from provider model")
    func availableVariants() {
        let providers = sampleProviders()
        #expect(ProviderSettingsLogic.availableVariants(for: "mycoder-auto-free", in: providers) == ["high", "low", "medium"])
        #expect(ProviderSettingsLogic.availableVariants(for: "plain-model", in: providers).isEmpty)
    }

    @Test("Normalizes variant when unsupported")
    func normalizeVariant() {
        let providers = sampleProviders()
        #expect(ProviderSettingsLogic.normalizedVariant("high", for: "mycoder-auto-free", in: providers) == "high")
        #expect(ProviderSettingsLogic.normalizedVariant("missing", for: "mycoder-auto-free", in: providers) == "high")
        #expect(ProviderSettingsLogic.normalizedVariant("high", for: "plain-model", in: providers) == nil)
    }

    @Test("Migrates legacy thinking levels to variant keys")
    func legacyThinkingMigration() {
        #expect(ProviderSettingsLogic.migrateLegacyThinkingLevel(ThinkingLevel.noThinking.rawValue) == "low")
        #expect(ProviderSettingsLogic.migrateLegacyThinkingLevel(ThinkingLevel.max.rawValue) == "high")
    }

    private func sampleProviders() -> [MimoProviderResponse] {
        [
            MimoProviderResponse(
                id: "mimo",
                name: "MiMo",
                models: [
                    "mycoder-auto-free": MimoProviderModel(
                        id: "mycoder-auto-free",
                        name: "myCoder Auto Free",
                        status: "active",
                        providerID: "mimo",
                        capabilities: MimoModelCapabilities(reasoning: true),
                        variants: [
                            "low": MimoModelVariant(reasoningEffort: "low"),
                            "medium": MimoModelVariant(reasoningEffort: "medium"),
                            "high": MimoModelVariant(reasoningEffort: "high")
                        ]
                    ),
                    "plain-model": MimoProviderModel(
                        id: "plain-model",
                        name: "Plain",
                        status: "active",
                        providerID: "mimo",
                        capabilities: MimoModelCapabilities(reasoning: false),
                        variants: nil
                    )
                ]
            )
        ]
    }
}

@Suite("Session Restore Selections")
struct SessionRestoreTests {

    @Test("Restores agent model and variant from last user message")
    func restoreFromMessages() throws {
        let json = """
        [
          {
            "info": {
              "id": "msg_user",
              "role": "user",
              "agent": "compose",
              "modelID": "mycoder-auto-free",
              "providerID": "mimo",
              "variant": "medium"
            },
            "parts": [{"type": "text", "text": "hello"}]
          }
        ]
        """.data(using: .utf8)!

        let messages = try JSONDecoder().decode([MimoMessageResponse].self, from: json)
        let selections = SessionSendLogic.restoreSelections(from: messages)
        #expect(selections?.agentMode == .compose)
        #expect(selections?.providerID == "mimo")
        #expect(selections?.modelID == "mycoder-auto-free")
        #expect(selections?.variant == "medium")
    }
}

@Suite("Message ID Generator")
struct MessageIDGeneratorTests {
    @Test("Generates msg prefixed IDs")
    func prefix() {
        let id = MessageIDGenerator.next()
        #expect(id.hasPrefix("msg_"))
    }

    @Test("Local provider ID is preserved, not resolved away")
    func preservesLocalProviderID() {
        let options = SessionSendLogic.buildSendOptions(
            agentMode: .build,
            selectedVariant: nil,
            modelID: "big-pickle",
            selectedProviderID: "oc-local-e2e",
            providers: [],
            customProviders: [],
            localProviderIDs: ["oc-local-e2e"]
        )
        #expect(options.providerID == "oc-local-e2e")
        #expect(options.modelID == "big-pickle")
    }

    @Test("Unknown provider ID still resolves via catalog")
    func unknownProviderFallsBackToCatalog() {
        let options = SessionSendLogic.buildSendOptions(
            agentMode: .build,
            selectedVariant: nil,
            modelID: "m",
            selectedProviderID: "nope",
            providers: [],
            customProviders: [],
            localProviderIDs: []
        )
        #expect(options.providerID == nil)
    }
}
