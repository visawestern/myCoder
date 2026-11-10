import Foundation
import Testing
@testable import myCoder

@Suite("BoundedProcessRunner")
struct BoundedProcessRunnerTests {
    @Test("вывод 200 КБ не вешает процесс")
    func largeOutput() {
        let r = BoundedProcessRunner.run(executable: "/bin/sh",
            arguments: ["-c", "head -c 200000 /dev/zero | tr '\\0' 'x'"], timeout: 10)
        #expect(!r.timedOut)
        #expect(r.exitCode == 0)
        #expect(r.stdout.utf8.count == 200_000)
    }

    @Test("таймаут убивает процесс")
    func timeout() {
        let r = BoundedProcessRunner.run(executable: "/bin/sh", arguments: ["-c", "sleep 30"], timeout: 1)
        #expect(r.timedOut)
        #expect(r.exitCode == 124)
    }

    @Test("вывод 3 МБ обрезается до лимита")
    func truncation() {
        let r = BoundedProcessRunner.run(executable: "/bin/sh",
            arguments: ["-c", "head -c 3000000 /dev/zero | tr '\\0' 'x'"], timeout: 10)
        #expect(r.truncated)
        #expect(r.stdout.utf8.count <= BoundedProcessRunner.maxStreamBytes)
    }
}
