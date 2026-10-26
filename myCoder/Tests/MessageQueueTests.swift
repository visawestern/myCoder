import Testing
import Foundation
@testable import myCoder

@Suite("MessageQueue")
struct MessageQueueTests {

    @Test("Queue starts empty")
    func startsEmpty() async {
        let queue = MessageQueue()
        #expect(queue.isEmpty == true)
        #expect(queue.pendingMessages.count == 0)
    }

    @Test("Queue clears on cancelAll")
    func cancelClears() async {
        let queue = MessageQueue()
        queue.enqueue(text: "msg1", type: .build)
        queue.enqueue(text: "msg2", type: .build)
        queue.cancelAll()
        #expect(queue.pendingMessages.count == 0)
    }

    @Test("Queue maintains FIFO order in pending list")
    func fifoOrder() async {
        let queue = MessageQueue()
        queue.enqueue(text: "msg1", type: .build)
        queue.enqueue(text: "msg2", type: .build)
        queue.enqueue(text: "msg3", type: .build)
        #expect(queue.pendingMessages.count == 3)
        let first = queue.pendingMessages.first
        #expect(first?.text == "msg1")
    }

    @Test("Enqueue waits until processing is explicitly requested")
    func enqueueWaitsForProcessing() {
        let queue = MessageQueue()
        var processed: [String] = []
        queue.setOnProcess { processed.append($0.text) }

        queue.enqueue(text: "later", type: .build)

        #expect(processed.isEmpty)
        #expect(queue.pendingMessages.map(\.text) == ["later"])

        queue.processNext()

        #expect(processed == ["later"])
        #expect(queue.pendingMessages.isEmpty)
    }

    @Test("CancelAll empties pending")
    func cancelEmptiesPending() async {
        let queue = MessageQueue()
        queue.enqueue(text: "msg1", type: .build)
        queue.enqueue(text: "msg2", type: .build)
        queue.cancelAll()
        #expect(queue.pendingMessages.count == 0)
    }
}
