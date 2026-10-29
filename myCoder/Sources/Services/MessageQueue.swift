import Foundation

struct QueuedMessage: Identifiable {
    let id = UUID()
    let text: String
    let files: [FileInfo]
    let images: [ClipboardImage]
    let type: MessageType
    /// Chat the message was queued in. A queued send must land in that chat
    /// even if the user opened another one before it started.
    let sessionID: String?
}

class MessageQueue: ObservableObject {
    @Published var pendingMessages: [QueuedMessage] = []
    /// While paused, completions do not auto-drain the queue. Force-send uses
    /// this so the interrupted turn cannot start the next item concurrently.
    @Published private(set) var isPaused = false

    private var onProcess: ((QueuedMessage) -> Void)?
    
    init() {}
    
    var isEmpty: Bool {
        pendingMessages.isEmpty
    }
    
    func setOnProcess(_ handler: @escaping (QueuedMessage) -> Void) {
        onProcess = handler
    }
    
    func enqueue(
        text: String,
        files: [FileInfo] = [],
        images: [ClipboardImage] = [],
        type: MessageType,
        sessionID: String? = nil
    ) {
        let msg = QueuedMessage(
            text: text,
            files: files,
            images: images,
            type: type,
            sessionID: sessionID
        )
        pendingMessages.append(msg)
    }
    
    func processNext() {
        guard !isPaused, let handler = onProcess, let first = pendingMessages.first else { return }
        pendingMessages.removeFirst()
        handler(first)
    }

    func pause() {
        isPaused = true
    }

    func resume() {
        isPaused = false
    }

    @discardableResult
    func remove(id: UUID) -> QueuedMessage? {
        guard let index = pendingMessages.firstIndex(where: { $0.id == id }) else { return nil }
        return pendingMessages.remove(at: index)
    }
    
    func cancelPending(at index: Int) {
        guard index >= 0 && index < pendingMessages.count else { return }
        pendingMessages.remove(at: index)
    }
    
    func cancelAll() {
        pendingMessages.removeAll()
    }
}
