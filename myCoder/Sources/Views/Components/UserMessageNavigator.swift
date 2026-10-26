import SwiftUI

/// Floating vertical navigator for the user's own messages. It stays pinned
/// to the trailing edge (like the scroll-to-bottom button), scrolls when the
/// chat has many turns, and shows a 100-character preview on hover.
struct UserMessageNavigator: View {
    let messages: [Message]
    let currentMessageID: String?
    /// User messages that precede the loaded page — the numbering continues
    /// from here so it matches the whole session.
    var offset: Int = 0
    let onSelect: (String) -> Void

    @State private var hoveredID: String?

    private var userMessages: [Message] {
        UserMessageNavigatorLogic.userMessages(messages)
    }

    private var currentIndex: Int? {
        userMessages.firstIndex { $0.id == currentMessageID }
    }

    var body: some View {
        if !userMessages.isEmpty {
            VStack(spacing: 3) {
                stepButton(icon: "chevron.up",
                           enabled: currentIndex != nil && currentIndex != 0) {
                    jump(direction: .up)
                }
                .accessibilityLabel("Previous message")

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 5) {
                        ForEach(Array(userMessages.enumerated()), id: \.element.id) { index, message in
                            navigatorButton(index: index, message: message)
                        }
                    }
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                }

                stepButton(icon: "chevron.down",
                           enabled: currentIndex != nil && currentIndex != userMessages.count - 1) {
                    jump(direction: .down)
                }
                .accessibilityLabel("Next message")
            }
            .frame(width: 24)
            .frame(maxHeight: 280)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.mimo.surface.opacity(0.72))
                    .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.mimo.border.opacity(0.55), lineWidth: 0.5)
            )
            .overlayPreferenceValue(UserMessageNavigatorAnchors.self) { anchors in
                GeometryReader { proxy in
                    if let hoveredID,
                       let message = userMessages.first(where: { $0.id == hoveredID }),
                       let anchor = anchors[hoveredID] {
                        let rect = proxy[anchor]
                        tooltip(for: message)
                            .position(
                                x: rect.minX - 118,
                                y: min(max(rect.midY, 32), proxy.size.height - 32)
                            )
                    }
                }
                .allowsHitTesting(false)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Your messages")
        }
    }

    private func jump(direction: UserMessageNavigatorLogic.NavigatorDirection) {
        guard let currentIndex,
              let next = UserMessageNavigatorLogic.steppedIndex(
                from: currentIndex,
                direction: direction,
                messageCount: userMessages.count
              ) else { return }
        onSelect(userMessages[next].id)
    }

    private func stepButton(icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .interfaceFont(size: 8, weight: .semibold)
                .foregroundColor(enabled ? Color.mimo.textSecondary : Color.mimo.textMuted.opacity(0.5))
                .frame(width: 18, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(HandCursorButtonStyle())
        .disabled(!enabled)
    }

    private func navigatorButton(index: Int, message: Message) -> some View {
        let isCurrent = message.id == currentMessageID
        return Button {
            onSelect(message.id)
        } label: {
            Text(UserMessageNavigatorLogic.buttonTitle(index: index, offset: offset))
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(
                    isCurrent
                        ? Color.white
                        : (hoveredID == message.id
                            ? Color.mimo.textPrimary
                            : Color.mimo.textSecondary)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: 18, height: 18)
                .background(
                    Circle().fill(
                        isCurrent
                            ? Color.mimo.brand
                            : (hoveredID == message.id
                                ? Color.mimo.brand.opacity(0.35)
                                : Color.mimo.surface.opacity(0.9))
                    )
                )
                .overlay(
                    Circle().stroke(Color.mimo.border.opacity(0.65), lineWidth: 0.5)
                )
                .contentShape(Circle())
        }
        .buttonStyle(HandCursorButtonStyle())
        .onHover { hovering in
            if hovering {
                hoveredID = message.id
            } else if hoveredID == message.id {
                hoveredID = nil
            }
        }
        .anchorPreference(
            key: UserMessageNavigatorAnchors.self,
            value: .bounds
        ) { [message.id: $0] }
        .accessibilityLabel("Your message \(index + offset + 1)")
        .accessibilityValue(UserMessageNavigatorLogic.preview(for: message))
    }

    private func tooltip(for message: Message) -> some View {
        Text(UserMessageNavigatorLogic.preview(for: message))
            .font(.system(size: 10))
            .foregroundColor(Color.mimo.textPrimary)
            .lineLimit(4)
            .multilineTextAlignment(.leading)
            .frame(width: 220, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.mimo.surface)
                    .shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.mimo.border.opacity(0.7), lineWidth: 0.5)
            )
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct UserMessageNavigatorAnchors: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(value: inout [String: Anchor<CGRect>],
                       nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
