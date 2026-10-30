import Foundation

/// Transport for Zen chat completions that runs the HTTPS request through the
/// locally installed `bun` runtime. Upstream serves the anonymous free tier
/// only to the official client's HTTP/TLS stack (verified 2026-10-25: the same
/// byte-identical payload from bun returns 200 while curl/node/go and Swift
/// URLSession hit the exhausted per-IP daily bucket, and a transparent TCP
/// relay keeps bun at 200 while mitm — which re-originates TLS — drops it to
/// 429). The protocol, headers, session identifiers and SSE parsing stay in
/// myCoder; only the TLS/HTTP leg is delegated to bun. When bun is absent the
/// URLSession path is used as before.
final class BunHTTPTransport: @unchecked Sendable {
    struct Opened {
        let statusCode: Int
        let errorBody: Data
        let lines: AsyncThrowingStream<String, Error>
    }

    static let script = #"""
    const input = await new Response(Bun.stdin.stream()).text();
    const cfg = JSON.parse(input);
    const res = await fetch(cfg.url, {
      method: "POST",
      headers: cfg.headers,
      body: Buffer.from(cfg.body, "base64"),
    });
    console.log("HTTP_STATUS " + res.status);
    if (!res.ok) {
      const text = await res.text();
      console.log("HTTP_ERROR_BODY " + Buffer.from(text.slice(0, 16384), "utf8").toString("base64"));
      process.exit(0);
    }
    const reader = res.body.getReader();
    const decoder = new TextDecoder();
    let buf = "";
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      buf += decoder.decode(value, { stream: true });
      const parts = buf.split("\n");
      buf = parts.pop() ?? "";
      for (const line of parts) console.log(line);
    }
    if (buf.length > 0) console.log(buf);
    """#

    static func open(url: URL, headers: [String: String], body: Data, bunPath: String) async throws -> Opened {
        let router = LineRouter()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: bunPath)
        process.arguments = ["-e", script]
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        let (lineStream, lineContinuation) = AsyncThrowingStream<String, Error>.makeStream()
        let (publicStream, publicContinuation) = AsyncThrowingStream<String, Error>.makeStream()
        router.setDownstream(publicContinuation)

        stderr.fileHandleForReading.readabilityHandler = { handle in
            if handle.availableData.isEmpty {
                handle.readabilityHandler = nil
            }
        }

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            for line in router.consume(chunk: chunk) {
                router.handle(line: line, into: lineContinuation)
            }
        }

        process.terminationHandler = { _ in
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            router.finish(error: nil)
        }

        try process.run()
        let payload = try JSONSerialization.data(withJSONObject: [
            "url": url.absoluteString,
            "headers": headers,
            "body": body.base64EncodedString(),
        ])
        stdin.fileHandleForWriting.write(payload)
        try stdin.fileHandleForWriting.close()

        lineContinuation.onTermination = { _ in
            if process.isRunning {
                process.terminate()
            }
        }

        let statusCode = try await router.awaitStatus()
        let errorBody = router.errorBody
        let forwardTask = Task {
            do {
                for try await line in lineStream {
                    publicContinuation.yield(line)
                }
                publicContinuation.finish()
            } catch {
                publicContinuation.finish(throwing: error)
            }
        }
        _ = forwardTask
        return Opened(statusCode: statusCode, errorBody: errorBody, lines: publicStream)
    }

    final class LineRouter: @unchecked Sendable {
        private let lock = NSLock()
        private var pending = Data()
        private var status: Int?
        private var storedErrorBody = Data()
        private var sawStatus = false
        private var finished = false
        private var storedError: Error?
        private var downstream: AsyncThrowingStream<String, Error>.Continuation?
        private var statusContinuation: CheckedContinuation<Int, Error>?

        func setDownstream(_ continuation: AsyncThrowingStream<String, Error>.Continuation) {
            lock.lock()
            downstream = continuation
            lock.unlock()
        }

        func consume(chunk: Data) -> [String] {
            lock.lock()
            defer { lock.unlock() }
            pending.append(chunk)
            var lines: [String] = []
            while let index = pending.firstIndex(of: 0x0A) {
                var line = String(decoding: pending[..<index], as: UTF8.self)
                if line.hasSuffix("\r") { line.removeLast() }
                pending.removeSubrange(...index)
                lines.append(line)
            }
            return lines
        }

        func handle(line: String, into continuation: AsyncThrowingStream<String, Error>.Continuation) {
            lock.lock()
            if !sawStatus, line.hasPrefix("HTTP_STATUS ") {
                status = Int(line.dropFirst("HTTP_STATUS ".count).trimmingCharacters(in: .whitespaces)) ?? 0
                sawStatus = true
                let pendingResume = statusContinuation
                statusContinuation = nil
                let value = status ?? 0
                lock.unlock()
                pendingResume?.resume(returning: value)
                return
            }
            if line.hasPrefix("HTTP_ERROR_BODY ") {
                storedErrorBody = Data(base64Encoded: String(line.dropFirst("HTTP_ERROR_BODY ".count))) ?? Data()
                lock.unlock()
                return
            }
            if sawStatus {
                continuation.yield(line)
            }
            lock.unlock()
        }

        func finish(error: Error?) {
            lock.lock()
            guard !finished else {
                lock.unlock()
                return
            }
            finished = true
            storedError = error
            let pendingResume = statusContinuation
            statusContinuation = nil
            let downstream = self.downstream
            let resolvedStatus = status ?? 0
            lock.unlock()
            if let pendingResume {
                if let error {
                    pendingResume.resume(throwing: error)
                } else {
                    pendingResume.resume(returning: resolvedStatus)
                }
            }
            if let error {
                downstream?.finish(throwing: error)
            } else {
                downstream?.finish()
            }
        }

        var errorBody: Data {
            lock.lock()
            defer { lock.unlock() }
            return storedErrorBody
        }

        func awaitStatus() async throws -> Int {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if let status {
                    lock.unlock()
                    continuation.resume(returning: status)
                    return
                }
                if let error = storedError {
                    lock.unlock()
                    continuation.resume(throwing: error)
                    return
                }
                statusContinuation = continuation
                lock.unlock()
            }
        }
    }
}
