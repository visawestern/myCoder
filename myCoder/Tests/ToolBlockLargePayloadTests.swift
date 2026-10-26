import Testing
import Foundation
@testable import myCoder

/// Live 2026-10-25: a model emitted a 16 KB `write_file` tool block and forgot
/// the final `}` of the outer object. The host silently dropped the call, the
/// loop treated the response as a final answer and the model kept apologizing
/// that "the system is not executing it". These tests pin the recovery and the
/// honest error feedback for shapes that cannot be repaired.
@Suite("Tool block parsing — large payloads and damaged JSON")
struct ToolBlockLargePayloadTests {

    private func toolBlock(json: String, preamble: String = "I will now emit the `write_file` tool.") -> String {
        """
        \(preamble)

        ```tool
        \(json)
        ```
        """
    }

    private func escapedHTMLPayload(lines: Int) -> String {
        var body = ""
        for index in 0..<lines {
            body += #"    <div class=\"row\" id=\"row-\#(index)\">cell text</div>\n"#
        }
        return #"<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n<title>Comparison</title>\n</head>\n<body>\n"# + body + #"</body>\n</html>"#
    }

    @Test("A large single-line payload is parsed")
    func largePayloadIsParsed() {
        let content = String(repeating: "line with <html lang=\"en\"> and \\n escapes; ", count: 400)
        let payload: [String: Any] = [
            "name": "write_file",
            "args": ["path": "project_comparison.html", "content": content]
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        let text = toolBlock(json: json)
        let calls = WebToolProtocolEmulator.parseToolCalls(from: text)
        #expect(calls.count == 1)
        #expect(calls.first?.name == "write_file")
        #expect(calls.first?.arguments["path"] == "project_comparison.html")
        #expect(calls.first?.arguments["content"]?.count == content.count)
    }

    @Test("A live-shaped body missing the outer closing brace is recovered")
    func missingOuterBraceIsRecovered() {
        let content = escapedHTMLPayload(lines: 30)
        let json = """
        {"name": "write_file", "args": {"path": "project_comparison.html", "content": "\(content)"
        }
        """
        let text = toolBlock(json: json)
        let calls = WebToolProtocolEmulator.parseToolCalls(from: text)
        #expect(calls.count == 1)
        #expect(calls.first?.name == "write_file")
        #expect(calls.first?.arguments["path"] == "project_comparison.html")
        #expect(calls.first?.arguments["content"]?.hasSuffix("</html>") == true)
        #expect(WebToolProtocolEmulator.malformedToolBlockFeedback(from: text) == nil)
    }

    @Test("A payload with raw newlines inside the string is recovered")
    func payloadWithRawNewlinesIsRecovered() {
        let text = toolBlock(json: """
        {"name": "write_file", "args": {"path": "a.html", "content": "line1
        line2"}}
        """)
        let calls = WebToolProtocolEmulator.parseToolCalls(from: text)
        #expect(calls.count == 1)
        #expect(calls.first?.arguments["content"] == "line1\nline2")
    }

    @Test("A payload with escaped quotes and backslashes is parsed")
    func payloadWithEscapesIsParsed() {
        let content = "a \"quoted\" word and a backslash \\ and a newline \n"
        let payload: [String: Any] = [
            "name": "write_file",
            "args": ["path": "x.html", "content": content]
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        let calls = WebToolProtocolEmulator.parseToolCalls(from: toolBlock(json: json))
        #expect(calls.count == 1)
        #expect(calls.first?.arguments["content"] == content)
    }

    @Test("An unterminated string is not executed and reports an error back")
    func unterminatedStringReportsError() {
        let text = toolBlock(json: """
        {"name": "write_file", "args": {"path": "a.html", "content": "<!DOCTYPE html>
        <html>never closed
        """)
        let calls = WebToolProtocolEmulator.parseToolCalls(from: text)
        #expect(calls.first?.arguments["__mycoder_truncated"] == "1")
        let feedback = WebToolProtocolEmulator.malformedToolBlockFeedback(from: text)
        #expect(feedback != nil)
        #expect(feedback?.contains("not terminated") == true)
        #expect(feedback?.contains("NOT executed") == true)
    }

    @Test("A fenced block missing closing brackets reports the count")
    func missingBracesReportCount() {
        let text = toolBlock(json: """
        {"name": "write_file", "args": {"path": "a.html", "content": "done"
        """)
        let calls = WebToolProtocolEmulator.parseToolCalls(from: text)
        #expect(calls.count == 1)
        let broken = toolBlock(json: """
        {"name": "write_file", "args": {"path": "a.html" "content": "done"}}
        """)
        #expect(WebToolProtocolEmulator.parseToolCalls(from: broken).isEmpty)
        let feedback = WebToolProtocolEmulator.malformedToolBlockFeedback(from: broken)
        #expect(feedback != nil)
    }

    @Test("A valid response without tool blocks yields no feedback")
    func validResponseYieldsNoFeedback() {
        #expect(WebToolProtocolEmulator.malformedToolBlockFeedback(from: "Just a plain answer.") == nil)
        #expect(WebToolProtocolEmulator.malformedToolBlockFeedback(from: "") == nil)
    }

    @Test("A repaired call is not reported as a final answer")
    func repairedCallIsNotFinal() {
        let content = escapedHTMLPayload(lines: 5)
        let text = toolBlock(json: """
        {"name": "write_file", "args": {"path": "x.html", "content": "\(content)"
        }
        """)
        #expect(WebToolProtocolEmulator.isFinalResponse(text) == false)
    }
}
