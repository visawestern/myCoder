import Testing
@testable import myCoder

/// Audit 2026-09-09 (Qwen live): the vendor renders an error placeholder
/// (div.response-message-empty — "The current content is empty, please
/// regenerate.") instead of a model answer when generation fails. None of
/// these may ever be presented as a real answer.
@Suite("Vendor error placeholders are never real answers")
struct WebVendorErrorPlaceholderTests {
    @Test func qwenEmptyPlaceholderIsRecognized() {
        #expect(WebVendorErrorPlaceholderLogic.isErrorPlaceholder(
            "The current content is empty, please regenerate."))
    }

    @Test func qwenEmptyPlaceholderIsNotARealAnswer() {
        #expect(!WebVendorErrorPlaceholderLogic.isGenuineAnswer(
            "The current content is empty, please regenerate."))
    }

    @Test func qwenEmptyPlaceholderIsNotAFinalResponse() {
        #expect(!WebToolProtocolEmulator.isFinalResponse(
            "The current content is empty, please regenerate."))
    }

    @Test func qwenEmptyPlaceholderFailsSendWaitContract() {
        #expect(!SendWaitAnswerLogic.isRealAnswer(
            "The current content is empty, please regenerate."))
    }

    @Test func errorElementMatchedByClass() {
        #expect(WebVendorErrorPlaceholderLogic.isErrorElement(
            classAttribute: "response-message-empty"))
        #expect(!WebVendorErrorPlaceholderLogic.isErrorElement(
            classAttribute: "markdown prose"))
    }

    @Test func realAnswersStillPass() {
        #expect(WebVendorErrorPlaceholderLogic.isGenuineAnswer("397"))
        #expect(WebVendorErrorPlaceholderLogic.isGenuineAnswer(
            "The directory contains .git, .mycoder and TZ-Bezdna-v3.md."))
        #expect(WebToolProtocolEmulator.isFinalResponse("397"))
        #expect(SendWaitAnswerLogic.isRealAnswer("397"))
    }

    @Test func localTurnErrorsAreNotRealAnswers() {
        // The send-and-wait contract reports these as status:error, never
        // as status:answered.
        #expect(!SendWaitAnswerLogic.isRealAnswer(
            "Web provider error: The provider reports its usage limit is reached."))
        #expect(!SendWaitAnswerLogic.isRealAnswer(
            "Web chat was not sent: binding failed"))
        #expect(!SendWaitAnswerLogic.isRealAnswer(
            "myCoder Auto Free error: boom"))
    }

    @Test func degenerateShortTextsNeverMatch() {
        #expect(!WebVendorErrorPlaceholderLogic.isErrorPlaceholder(""))
        #expect(!WebVendorErrorPlaceholderLogic.isErrorPlaceholder("ok"))
    }
}
