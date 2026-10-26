import Foundation
import Testing
@testable import myCoder

@Suite("PROV-08 provider connection validation")
struct ProviderConnectionValidationLogicTests {
    @Test("valid OpenAI-compatible model response is connected")
    func validModelResponse() {
        let body = Data(#"{"data":[{"id":"gpt-test"}]}"#.utf8)
        #expect(ProviderConnectionValidationLogic.isValidModelsResponse(statusCode: 200, body: body))
    }

    @Test("HTTP success with invalid body is not connected")
    func invalidBodyFails() {
        #expect(!ProviderConnectionValidationLogic.isValidModelsResponse(statusCode: 200, body: Data("<html>login</html>".utf8)))
    }

    @Test("blank alternate ID falls back to a valid model name")
    func blankAlternateIDUsesName() {
        let body = Data(#"{"models":[{"id":"  ","name":"qwen-coder"}]}"#.utf8)
        #expect(ProviderConnectionValidationLogic.isValidModelsResponse(statusCode: 200, body: body))
    }

    @Test("model extraction filters blanks, falls back to names, and deduplicates")
    func modelExtractionIsCanonical() {
        let body = Data(#"{"data":[{"id":"  "},{"id":"gpt-test"},{"id":"gpt-test"}],"models":[{"id":" ","name":"models/qwen-coder"}]}"#.utf8)
        #expect(ProviderConnectionValidationLogic.modelIDs(from: body) == ["gpt-test", "qwen-coder"])
    }

    @Test("empty model list is not connected")
    func emptyModelsFail() {
        let body = Data(#"{"data":[]}"#.utf8)
        #expect(!ProviderConnectionValidationLogic.isValidModelsResponse(statusCode: 200, body: body))
    }

    @Test("non-success HTTP status is not connected even with model JSON")
    func nonSuccessFails() {
        let body = Data(#"{"data":[{"id":"gpt-test"}]}"#.utf8)
        #expect(!ProviderConnectionValidationLogic.isValidModelsResponse(statusCode: 401, body: body))
    }
}
