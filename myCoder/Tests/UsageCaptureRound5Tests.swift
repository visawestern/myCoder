import Testing
import Foundation
@testable import myCoder

@Suite("DirectChatResult structure (round 5)")
struct DirectChatResultTests {

    @Test func resultCarriesContentAndUsage() {
        let usage = UsageCapture(promptTokens: 100, completionTokens: 50, costUSD: 0.02, modelID: "gpt-4o", providerID: "openai")
        let result = DirectChatResult(content: "Hello world", usage: usage)
        #expect(result.content == "Hello world")
        #expect(result.usage?.promptTokens == 100)
    }

    @Test func resultWithNilUsageForLocalProvider() {
        let result = DirectChatResult(content: "Hi", usage: nil)
        #expect(result.content == "Hi")
        #expect(result.usage == nil)
    }

    @Test func resultEquatable() {
        let u = UsageCapture(promptTokens: 1, completionTokens: 1, costUSD: nil, modelID: "m", providerID: "p")
        let a = DirectChatResult(content: "x", usage: u)
        let b = DirectChatResult(content: "x", usage: u)
        let c = DirectChatResult(content: "y", usage: u)
        #expect(a == b)
        #expect(a != c)
    }

    @Test func convenienceFromContentOnly() {
        let result = DirectChatResult(content: "just text")
        #expect(result.content == "just text")
        #expect(result.usage == nil)
    }
}
