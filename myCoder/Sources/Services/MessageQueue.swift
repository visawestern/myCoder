import Foundation

struct QueuedMessage: Identifiable {
    let id = UUID()
    let text: String
    let files: [FileInfo]
    let images: [ClipboardImage]
    let type: MessageType
}

class MessageQueue: ObservableObject {
    @Published var pendingMessages: [QueuedMessage] = []
    
    private var onProcess: ((QueuedMessage) -> Void)?
    
    init() {}
    
    var isEmpty: Bool {
        pendingMessages.isEmpty
    }
    
    func setOnProcess(_ handler: @escaping (QueuedMessage) -> Void) {
        onProcess = handler
    }
    
    func enqueue(text: String, files: [FileInfo] = [], images: [ClipboardImage] = [], type: MessageType) {
        let msg = QueuedMessage(text: text, files: files, images: images, type: type)
        pendingMessages.append(msg)
    }
    
    func processNext() {
        guard let handler = onProcess, let first = pendingMessages.first else { return }
        pendingMessages.removeFirst()
        handler(first)
    }
    
    func cancelPending(at index: Int) {
        guard index >= 0 && index < pendingMessages.count else { return }
        pendingMessages.remove(at: index)
    }
    
    func cancelAll() {
        pendingMessages.removeAll()
    }
}
