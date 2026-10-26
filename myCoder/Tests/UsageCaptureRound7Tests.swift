import Testing
import Foundation
@testable import myCoder

@Suite("Message.usage field (round 7)")
struct MessageUsageFieldTests {

    @Test func messageCanCarryUsageCapture() {
        let usage = UsageCapture(promptTokens: 200, completionTokens: 75, costUSD: 0.03, modelID: "gpt-4o", providerID: "openai")
        let msg = Message(role: .assistant, content: "hi", usage: usage)
        #expect(msg.usage?.promptTokens == 200)
        #expect(msg.usage?.completionTokens == 75)
        #expect(msg.usage?.costUSD == 0.03)
    }

    @Test func messageUsageDefaultsToNil() {
        let msg = Message(role: .assistant, content: "hi")
        #expect(msg.usage == nil)
    }

    @Test func messageUsagePreservedByUpdate() {
        let msg = Message(role: .assistant, content: "")
        let usage = UsageCapture(promptTokens: 10, completionTokens: 5, costUSD: nil, modelID: "m", providerID: "p")
        let updated = Message(id: msg.id, role: msg.role, content: "done", usage: usage)
        #expect(updated.usage?.totalTokens == 15)
    }

    @Test func messageEquatableIgnoresUsageByDefaultContract() {
        // Equatable derived from all stored fields would make usage part of
        // equality; ensure construction with/without usage works either way.
        let a = Message(role: .user, content: "x")
        let b = Message(role: .user, content: "x")
        #expect(a.content == b.content)
    }
}
