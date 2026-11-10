import Foundation

struct BoundedProcessResult: Equatable {
    var stdout: String
    var stderr: String
    var exitCode: Int32
    var timedOut: Bool
    var truncated: Bool
    var launchError: String?
    /// stdout, затем stderr (так раньше делал ProjectShellRunner).
    var output: String { stdout + stderr }
}

/// Запускает процесс, читает вывод ВО ВРЕМЯ работы (иначе pipe на 64 КБ вешает процесс),
/// ограничивает размер вывода и время.
enum BoundedProcessRunner {
    static let maxStreamBytes = 1_000_000

    static func run(executable: String,
                    arguments: [String],
                    workingDirectory: String? = nil,
                    timeout: TimeInterval = 30,
                    standardInputText: String? = nil) -> BoundedProcessResult {
        let cap = maxStreamBytes
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }
        let outPipe = Pipe()
        let errPipe = Pipe()
        let inPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = standardInputText == nil ? FileHandle.nullDevice : inPipe

        let lock = NSLock()
        var outData = Data()
        var errData = Data()
        var truncated = false
        let outEOF = DispatchSemaphore(value: 0)
        let errEOF = DispatchSemaphore(value: 0)

        func attach(_ pipe: Pipe, eof: DispatchSemaphore, store: @escaping (Data) -> Void) {
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {            // EOF
                    handle.readabilityHandler = nil
                    eof.signal()
                    return
                }
                store(chunk)
            }
        }
        attach(outPipe, eof: outEOF) { chunk in
            lock.lock(); defer { lock.unlock() }
            let room = cap - outData.count
            if room > 0 { outData.append(chunk.prefix(room)) }
            if chunk.count > room { truncated = true }
        }
        attach(errPipe, eof: errEOF) { chunk in
            lock.lock(); defer { lock.unlock() }
            let room = cap - errData.count
            if room > 0 { errData.append(chunk.prefix(room)) }
            if chunk.count > room { truncated = true }
        }

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }   // ДО run()
        do {
            try process.run()
        } catch {
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            return BoundedProcessResult(stdout: "", stderr: "", exitCode: -1, timedOut: false,
                                        truncated: false,
                                        launchError: "failed to launch: \(error.localizedDescription)")
        }
        if let text = standardInputText {
            try? inPipe.fileHandleForWriting.write(contentsOf: Data(text.utf8))
            try? inPipe.fileHandleForWriting.close()
        }

        var timedOut = false
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()                                  // SIGTERM
            if exited.wait(timeout: .now() + 2) == .timedOut {
                kill(process.processIdentifier, SIGKILL)         // если игнорирует SIGTERM
                _ = exited.wait(timeout: .now() + 2)
            }
        }
        // Дочитать хвост. Ждём EOF не дольше 1 с: если внук-процесс держит pipe, не зависаем.
        _ = outEOF.wait(timeout: .now() + 1)
        _ = errEOF.wait(timeout: .now() + 1)
        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil

        lock.lock(); defer { lock.unlock() }
        return BoundedProcessResult(
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self),
            exitCode: timedOut ? 124 : process.terminationStatus,
            timedOut: timedOut,
            truncated: truncated,
            launchError: nil)
    }
}
