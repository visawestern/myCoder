import Testing
import Foundation
@testable import myCoder

@Suite("Bun transport — line routing and detection")
struct AutoFreeBunTransportTests {

    @Test("Status line resolves awaitStatus and is hidden from SSE lines")
    func statusLineRouting() async throws {
        let router = makeRouter()
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        router.setDownstream(continuation)
        let statusTask = Task { try await router.awaitStatus() }
        for line in ["HTTP_STATUS 200", "data: {\"a\":1}", "data: [DONE]"] {
            router.handle(line: line, into: continuation)
        }
        let status = try await statusTask.value
        #expect(status == 200)
        router.finish(error: nil)
        var seen: [String] = []
        for try await line in stream {
            seen.append(line)
        }
        #expect(seen == ["data: {\"a\":1}", "data: [DONE]"])
    }

    @Test("Error body line is captured and not forwarded")
    func errorBodyRouting() async throws {
        let router = makeRouter()
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        router.setDownstream(continuation)
        let payload = Data("{\"error\":\"quota\"}".utf8).base64EncodedString()
        let statusTask = Task { try await router.awaitStatus() }
        for line in ["HTTP_STATUS 429", "HTTP_ERROR_BODY \(payload)"] {
            router.handle(line: line, into: continuation)
        }
        let status = try await statusTask.value
        #expect(status == 429)
        #expect(String(decoding: router.errorBody, as: UTF8.self) == "{\"error\":\"quota\"}")
        continuation.finish()
        var seen: [String] = []
        for try await line in stream {
            seen.append(line)
        }
        #expect(seen.isEmpty)
    }

    @Test("Chunked input reassembles lines split across reads")
    func chunkReassembly() {
        let router = makeRouter()
        var out: [String] = []
        out.append(contentsOf: router.consume(chunk: Data("data: one\nda".utf8)))
        out.append(contentsOf: router.consume(chunk: Data("ta: two\n".utf8)))
        #expect(out == ["data: one", "data: two"])
        out.append(contentsOf: router.consume(chunk: Data("trailing".utf8)))
        #expect(out.count == 2)
    }

    @Test("Finish without status throws to awaitStatus")
    func finishWithoutStatusThrows() async throws {
        let router = makeRouter()
        let task = Task { try await router.awaitStatus() }
        router.finish(error: BunTransportError.processDied)
        do {
            _ = try await task.value
            #expect(Bool(false), "expected throw")
        } catch {
            #expect(error is BunTransportError)
        }
    }

    @Test("bun detection returns a path when bun is installed and nil when disabled")
    func bunDetection() {
        let disabled = setenv("MYCODER_BUN_TRANSPORT", "0", 1)
        #expect(disabled == 0)
        #expect(MyCoderAutoFreeClient.bunExecutablePath() == nil)
        unsetenv("MYCODER_BUN_TRANSPORT")
        let path = MyCoderAutoFreeClient.bunExecutablePath()
        if path != nil {
            #expect(FileManager.default.isExecutableFile(atPath: path!))
        }
    }

    private func makeRouter() -> BunHTTPTransport.LineRouter {
        BunHTTPTransport.LineRouter()
    }
}

enum BunTransportError: Error {
    case processDied
}
