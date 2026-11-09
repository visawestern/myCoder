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
        var scan = normalizedPrefix(message.content, limit: limit)
        if scan.text.isEmpty, let files = message.files {
            scan = normalizedPrefix(files.map(\.name).joined(separator: ", "), limit: limit)
        }
        let text = scan.text.trimmingCharacters(in: .whitespaces)
        guard limit > 0, scan.hasMore else { return text }
        return text + "…"
    }

    /// The first `limit` characters of the whitespace-normalized text, and
    /// whether more normalized text follows.
    ///
    /// The scan STOPS as soon as the prefix is complete. Normalizing the
    /// whole message on every render froze the app on a megabyte-long paste
    /// (the navigator is re-evaluated on every layout pass), so only the
    /// beginning of the text is ever read.
    static func normalizedPrefix<Characters: Sequence>(
        _ characters: Characters,
        limit: Int
    ) -> (text: String, hasMore: Bool) where Characters.Element == Character {
        guard limit > 0 else { return ("", false) }
        var result = ""
        result.reserveCapacity(limit)
        var count = 0
        var pendingSpace = false
        var hasMore = false

        for character in characters {
            if character.isWhitespace {
                if count > 0 { pendingSpace = true }
                continue
            }
            if pendingSpace {
                pendingSpace = false
                if count >= limit { hasMore = true; break }
                result.append(" ")
                count += 1
            }
            if count >= limit { hasMore = true; break }
            result.append(character)
            count += 1
        }
        return (result, hasMore)
    }

    static func buttonTitle(index: Int, offset: Int = 0) -> String {
        "\(index + offset + 1)"
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
    /// Content-relative space for row frames: they change only when content
    /// is added/removed, NOT on every scroll tick. Visibility is derived from
    /// the NSScrollView offset instead of per-frame preferences.
    static let content = "chat-content-space"
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

/// Frame of the bottom sentinel in the chat scroll space. The old
/// `onAppear`/`onDisappear` pair was useless inside a `LazyVStack`: the sentinel
/// stays instantiated after the first layout, so "visible" never became false
/// and every streamed token yanked the reader to the bottom.
struct ChatBottomFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect,
                       nextValue: () -> CGRect) {
        value = nextValue()
    }
}
