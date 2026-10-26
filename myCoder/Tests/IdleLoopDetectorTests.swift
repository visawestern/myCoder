import Testing
import Foundation
@testable import myCoder

@Suite("Idle-loop detector C3 (eval harness-tax)")
struct IdleLoopDetectorTests {

    private func call(_ name: String, _ args: [String: String] = [:]) -> WebToolCall {
        WebToolCall(name: name, arguments: args)
    }

    @Test func thirdRepeatTriggersIdle() {
        var d = IdleLoopDetector()
        #expect(d.observe(call("list_dir", ["path": "."])) == false)
        #expect(d.observe(call("list_dir", ["path": "."])) == false)
        #expect(d.observe(call("list_dir", ["path": "."])) == true)
    }

    @Test func differentCallResetsStreak() {
        var d = IdleLoopDetector()
        #expect(d.observe(call("list_dir", ["path": "."])) == false)
        #expect(d.observe(call("list_dir", ["path": "."])) == false)
        #expect(d.observe(call("read_file", ["path": "a.txt"])) == false)
        #expect(d.observe(call("list_dir", ["path": "."])) == false)
        #expect(d.observe(call("list_dir", ["path": "."])) == false)
        #expect(d.observe(call("list_dir", ["path": "."])) == true)
    }

    @Test func sameNameDifferentArgsIsNotIdle() {
        var d = IdleLoopDetector()
        #expect(d.observe(call("read_file", ["path": "a.txt"])) == false)
        #expect(d.observe(call("read_file", ["path": "b.txt"])) == false)
        #expect(d.observe(call("read_file", ["path": "c.txt"])) == false)
    }

    @Test func idleStepsCountRepeats() {
        var d = IdleLoopDetector()
        _ = d.observe(call("list_dir", ["path": "."]))
        _ = d.observe(call("list_dir", ["path": "."]))
        #expect(d.idleSteps == 1)
        _ = d.observe(call("read_file", ["path": "a.txt"]))
        #expect(d.idleSteps == 1)
    }

    @Test func hardCapIs40() {
        #expect(IdleLoopDetector.hardIterationCap == 40)
        #expect(WebChatDriver.effectiveMaxIterations(configured: 25) == 25)
        #expect(WebChatDriver.effectiveMaxIterations(configured: 100) == 40)
        #expect(WebChatDriver.effectiveMaxIterations(configured: 40) == 40)
    }
}
