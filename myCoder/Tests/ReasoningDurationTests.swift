import Testing
import Foundation
@testable import myCoder

@Suite("Message — reasoningDuration freezes at completion")
struct ReasoningDurationTests {

    @Test("duration grows while reasoning is in progress (no end timestamp)")
    func durationGrowsWhileInProgress() {
        let start = Date().addingTimeInterval(-5)
        var msg = Message(role: .assistant, content: "")
        msg.reasoningStartedAt = start
        msg.reasoningEndedAt = nil

        let d1 = msg.reasoningDuration!
        #expect(d1 >= 4.9, "duration should measure from start to now")
    }

    @Test("duration freezes once reasoningEndedAt is set")
    func durationFreezesAtEnd() {
        let start = Date().addingTimeInterval(-10)
        let end = Date().addingTimeInterval(-3) // ended 3s ago
        var msg = Message(role: .assistant, content: "")
        msg.reasoningStartedAt = start
        msg.reasoningEndedAt = end

        let d = msg.reasoningDuration!
        #expect(abs(d - 7.0) < 0.5, "duration should be ~7s (start→end), not growing")
    }

    @Test("duration is nil when reasoning never started")
    func durationNilWithoutStart() {
        let msg = Message(role: .assistant, content: "hi")
        #expect(msg.reasoningDuration == nil)
    }

    @Test("without end timestamp, duration approximates elapsed time")
    func noEndTimeUsesNow() {
        let start = Date().addingTimeInterval(-2)
        var msg = Message(role: .assistant, content: "")
        msg.reasoningStartedAt = start

        let d = msg.reasoningDuration!
        #expect(d >= 1.9 && d < 3.0, "should be ~2s elapsed")
    }
}
