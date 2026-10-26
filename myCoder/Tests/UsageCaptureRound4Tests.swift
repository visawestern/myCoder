import Testing
import Foundation
@testable import myCoder

@Suite("ACPClient response usage contract (round 4)")
struct ACPUsageContractTests {

    @Test func responseDecodesUsageField() throws {
        let json = """
        {"id":"abc","object":"chat.completion","created":1700000000,"model":"gpt-4o",
         "choices":[{"index":0,"message":{"role":"assistant","content":"hi"},"finish_reason":"stop"}],
         "usage":{"prompt_tokens":123,"completion_tokens":45,"total_tokens":168}}
        """
        let data = json.data(using: .utf8)!
        let resp = try JSONDecoder().decode(ACPChatResponse.self, from: data)
        let usage = try #require(resp.usage)
        #expect(usage.promptTokens == 123)
        #expect(usage.completionTokens == 45)
        #expect(usage.totalTokens == 168)
    }

    @Test func responseDecodesMissingUsageAsNil() throws {
        let json = """
        {"id":"abc","object":"chat.completion","created":1700000000,"model":"gpt-4o",
         "choices":[{"index":0,"message":{"role":"assistant","content":"hi"},"finish_reason":"stop"}]}
        """
        let data = json.data(using: .utf8)!
        let resp = try JSONDecoder().decode(ACPChatResponse.self, from: data)
        #expect(resp.usage == nil)
    }

    @Test func fullRoundTripThroughCapture() throws {
        let json = """
        {"id":"abc","object":"chat.completion","created":1700000000,"model":"gpt-4o",
         "choices":[{"index":0,"message":{"role":"assistant","content":"hi"},"finish_reason":"stop"}],
         "usage":{"prompt_tokens":123,"completion_tokens":45,"total_tokens":168}}
        """
        let resp = try JSONDecoder().decode(ACPChatResponse.self, from: json.data(using: .utf8)!)
        let capture = UsageCapture(acpUsage: resp.usage!, modelID: resp.model, providerID: "openai")
        #expect(capture.promptTokens == 123)
        #expect(capture.completionTokens == 45)
        #expect(capture.modelID == "gpt-4o")
        #expect(capture.hasCost == false)
    }
}
