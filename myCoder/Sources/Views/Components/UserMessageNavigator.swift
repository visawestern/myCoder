import SwiftUI

/// Floating vertical navigator for the user's own messages.
///
/// It renders the SESSION-WIDE index (`UserMessageIndexEntry`), not the loaded
/// history page: every question the user ever asked gets a number, even when
/// its page is not in memory. The list is lazy and scrollable, so a chat with
/// thousands of messages still opens instantly. Selecting a number asks the
/// chat to load the target window and jump to it without animation.
///
/// Input: ordered entries, the active message id, and a selection callback.
/// Output: the numbered list + up/down step buttons.
/// Dependencies: `UserMessageNavigatorLogic` for preview/step rules.
struct UserMessageNavigator: View {
    let entries: [UserMessageIndexEntry]
    let currentMessageID: String?
    let onSelect: (String) -> Void

    @State private var hoveredID: String?
    /// While the pointer is over the list the user is scrolling it manually;
    /// auto-centering would fight that gesture and look like the list is
    /// "rushing". Centering resumes when the pointer leaves.
    @State private var isHoveringList = false
    /// Debounce for highlight-driven centering. Scrolling the chat changes the
    /// active message many times per second; centering on every change made
    /// the navigator jump around.
    @State private var centerTask: Task<Void, Never>?

    private var currentIndex: Int? {
        entries.firstIndex { $0.id == currentMessageID }
    }

    var body: some View {
        if !entries.isEmpty {
            VStack(spacing: 3) {
                stepButton(icon: "chevron.up",
                           enabled: currentIndex != nil && currentIndex != 0) {
                    jump(direction: .up)
                }
                .accessibilityLabel(L.t("Previous message"))

                ScrollViewReader { scrollProxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        // Lazy: only the visible numbers are built. A 10k
                        // message chat must not create 10k buttons on open.
                        LazyVStack(spacing: 5) {
                            ForEach(entries) { entry in
                                navigatorButton(entry: entry)
                            }
                        }
                        .padding(.vertical, 6 + UserMessageNavigatorLogic.verticalPadding(
                            itemCount: entries.count
                        ))
                        .frame(maxWidth: .infinity)
                    }
                    .onHover { hovering in
                        isHoveringList = hovering
                        if !hovering {
                            scheduleCenter(using: scrollProxy)
                        }
                    }
                    // Держим текущий номер в поле зрения навигатора, но без
                    // анимации и с задержкой: иначе каждый тик скролла чата
                    // перезапускал анимированную прокрутку списка.
                    .onChange(of: currentMessageID) { _ in
                        scheduleCenter(using: scrollProxy)
                    }
                    .onAppear {
                        scheduleCenter(using: scrollProxy)
                    }
                }

                stepButton(icon: "chevron.down",
                           enabled: currentIndex != nil && currentIndex != entries.count - 1) {
                    jump(direction: .down)
                }
                .accessibilityLabel(L.t("Next message"))
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
                       let entry = entries.first(where: { $0.id == hoveredID }),
                       let anchor = anchors[hoveredID] {
                        let rect = proxy[anchor]
                        tooltip(for: entry)
                            .position(
                                x: rect.minX - 118,
                                y: min(max(rect.midY, 32), proxy.size.height - 32)
                            )
                    }
                }
                .allowsHitTesting(false)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L.t("Your messages"))
        }
    }

    /// Debounced, non-animated centering of the active number.
    ///
    /// - Parameter proxy: navigator list scroll proxy.
    private func scheduleCenter(using proxy: ScrollViewProxy) {
        centerTask?.cancel()
        guard let id = currentMessageID, !isHoveringList else { return }
        centerTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled, !isHoveringList else { return }
            // `scrollTo` before the first layout pass is ignored; the next
            // runloop tick is when the lazy list has real rows.
            DispatchQueue.main.async {
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    private func jump(direction: UserMessageNavigatorLogic.NavigatorDirection) {
        guard let currentIndex,
              let next = UserMessageNavigatorLogic.steppedIndex(
                from: currentIndex,
                direction: direction,
                messageCount: entries.count
              ) else { return }
        onSelect(entries[next].id)
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

    private func navigatorButton(entry: UserMessageIndexEntry) -> some View {
        let isCurrent = entry.id == currentMessageID
        return Button {
            onSelect(entry.id)
        } label: {
            Text("\(entry.ordinal)")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(
                    isCurrent
                        ? Color.white
                        : (hoveredID == entry.id
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
                            : (hoveredID == entry.id
                                ? Color.mimo.brand.opacity(0.35)
                                : Color.mimo.surface.opacity(0.9))
                    )
                )
                .overlay(
                    Circle().stroke(
                        isCurrent ? Color.mimo.brand : Color.mimo.border.opacity(0.65),
                        lineWidth: isCurrent ? 1.5 : 0.5
                    )
                )
                .shadow(
                    color: isCurrent ? Color.mimo.brand.opacity(0.55) : .clear,
                    radius: isCurrent ? 5 : 0
                )
                .contentShape(Circle())
        }
        .buttonStyle(HandCursorButtonStyle())
        .onHover { hovering in
            if hovering {
                hoveredID = entry.id
            } else if hoveredID == entry.id {
                hoveredID = nil
            }
        }
        .anchorPreference(
            key: UserMessageNavigatorAnchors.self,
            value: .bounds
        ) { [entry.id: $0] }
        .accessibilityLabel(L.t("Your message %d", entry.ordinal))
        .accessibilityValue(entry.preview)
    }

    private func tooltip(for entry: UserMessageIndexEntry) -> some View {
        Text(entry.preview)
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
