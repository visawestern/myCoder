import SwiftUI
import AppKit

/// Telegram-style floating button that jumps the chat back to the latest message.
struct ScrollToBottomButton: View {
    let action: () -> Void
    @State var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.down")
                .interfaceFont(size: 14, weight: .semibold)
                .foregroundColor(Color.mimo.textPrimary)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Color.mimo.surface)
                        .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 3)
                )
                .overlay(
                    Circle().stroke(Color.mimo.border.opacity(isHovering ? 0.9 : 0.5), lineWidth: 1)
                )
                .contentShape(Circle())
        }
        .buttonStyle(HandCursorButtonStyle())
        .onHover { isHovering = $0 }
        .accessibilityLabel("Scroll to latest message")
    }
}



/// Reports a chat message row's frame in the chat scroll space (used to
/// resolve the currently visible user message for the navigator).
struct ChatRowFrameReporter: ViewModifier {
    let rowID: String
    let isUser: Bool
    let isLatest: Bool

    func body(content: Content) -> some View {
        if isUser || isLatest {
            content.background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ChatRowFrameKey.self,
                        // Content-relative: стабильно при скролле, меняется
                        // только когда реально меняется контент.
                        value: [rowID: geo.frame(in: .named(ChatScrollSpace.content))]
                    )
                }
            )
        } else {
            content
        }
    }
}

extension View {
    func chatRowFrameReporter(id: String, isUser: Bool, isLatest: Bool = false) -> some View {
        modifier(ChatRowFrameReporter(rowID: id, isUser: isUser, isLatest: isLatest))
    }
}

/// Names the chat scroll coordinate space and reports the visible viewport
/// frame inside it.
struct ChatScrollSpaceReporter: ViewModifier {
    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: ChatScrollSpace.name)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ChatViewportFrameKey.self,
                        value: geo.frame(in: .named(ChatScrollSpace.name))
                    )
                }
            )
    }
}

extension View {
    func chatScrollSpaceReporter() -> some View {
        modifier(ChatScrollSpaceReporter())
    }
}
