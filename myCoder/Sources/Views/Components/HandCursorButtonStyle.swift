import AppKit
import SwiftUI

/// Button style that keeps the plain look, points the mouse cursor with the
/// hand while hovering, and gives a subtle hover tint so interactive rows
/// react to the pointer. Replaces `.buttonStyle(HandCursorButtonStyle())` across the app: a
/// bare plain button on macOS inherits the text-insertion cursor above its
/// label, which reads as "this is text" instead of "this is clickable".
struct HandCursorButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HandCursorBody(configuration: configuration)
    }

    private struct HandCursorBody: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.6 : (hovering ? 0.82 : 1.0))
                .onHover { hovering in
                    self.hovering = hovering
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
        }
    }
}

/// Attaches the pointing-hand cursor to any view (rows, cards, links).
struct HandCursorModifier: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                hovering = inside
                if inside {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .opacity(hovering ? 0.92 : 1.0)
    }
}

extension View {
    func pointingHandCursor() -> some View {
        modifier(HandCursorModifier())
    }
}
