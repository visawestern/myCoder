import Foundation
import SwiftUI

/// Pure helpers for the floating chat navigator that jumps between the
/// user's own messages. Kept out of the view so the filtering, whitespace
/// normalization and 100-character hover preview are covered by tests.
enum UserMessageNavigatorLogic {
    static let previewCharacterLimit = 100

    /// User messages the navigator can jump to: the user's own messages that
    /// carry something to show.
    static func userMessages(_ messages: [Message]) -> [Message] {
        messages.filter { message in
            message.role == .user && !preview(for: message).isEmpty
        }
    }

    static func userMessageCount(_ messages: [Message]) -> Int {
        userMessages(messages).count
    }

    static func preview(for message: Message,
                        limit: Int = previewCharacterLimit) -> String {
        var text = normalized(message.content)
        if text.isEmpty, let files = message.files {
            text = normalized(files.map(\.name).joined(separator: ", "))
        }
        guard limit > 0, text.count > limit else { return text }
        let prefix = String(text.prefix(limit))
            .trimmingCharacters(in: .whitespaces)
        return prefix + "…"
    }

    static func buttonTitle(index: Int, offset: Int = 0) -> String {
        "\(index + offset + 1)"
    }

    private static func normalized(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}

extension UserMessageNavigatorLogic {
    /// Sweep direction along the user-message list.
    enum NavigatorDirection {
        case up
        case down
    }

    /// Index to jump to when stepping from `currentIndex`. Returns nil at the
    /// edges so callers can disable the corresponding button.
    static func steppedIndex(from currentIndex: Int,
                             direction: NavigatorDirection,
                             messageCount: Int) -> Int? {
        guard messageCount > 0 else { return nil }
        let next = currentIndex + (direction == .up ? -1 : 1)
        return (0..<messageCount).contains(next) ? next : nil
    }

    /// The user message the reader is currently looking at: the one whose
    /// band contains the viewport's middle line, or the last message whose
    /// bottom edge sits above it.
    static func currentUserMessageID(visibleRect: CGRect?,
                                     frames: [String: CGRect],
                                     messages: [Message]) -> String? {
        guard let visible = visibleRect, visible.height > 0, !frames.isEmpty else { return nil }
        let probe = visible.midY
        let bands: [(String, CGRect)] = messages.compactMap { message in
            guard let frame = frames[message.id], frame.height > 0 else { return nil }
            return (message.id, frame)
        }
        for (id, band) in bands where band.minY <= probe && band.maxY > probe {
            return id
        }
        let above = bands.filter { $0.1.maxY <= probe }
        if let last = above.last { return last.0 }
        return bands.first?.0
    }
}

/// Names the coordinate space in which chat rows report their frames so the
/// navigator can resolve the currently visible user message.
enum ChatScrollSpace {
    static let name = "chat-scroll-space"
}

struct ChatRowFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect],
                       nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct ChatViewportFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect,
                       nextValue: () -> CGRect) {
        value = nextValue()
    }
}
