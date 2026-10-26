import SwiftUI
import AppKit

/// In-chat browser for a web provider (user directive 2026-09-09, refined:
/// a small minimap-like window, NOT a full-width half-chat block).
///
/// - Minimap (default): a small live thumbnail pinned to the chat's
///   bottom-trailing corner, like an IDE minimap — the vendor page keeps
///   rendering there (which also keeps layout-driven DOM reads working).
///   Tapping it expands to the half-chat panel.
/// - Expanded: the half-chat panel with the full page, resizable, with
///   buttons to collapse back to the minimap or hide entirely.
///
/// Both modes re-parent the SAME pooled WKWebView — collapsing/hiding parks
/// it in a hidden host window WITHOUT destroying it, so login, conversation
/// and in-flight streams survive across requests and chats.
struct WebProviderBrowserPanel<Content: View>: View {
    let config: WebBrowserPanelConfig
    let isExpanded: Bool
    let onExpand: () -> Void
    let onCollapseToMini: () -> Void
    let onHide: () -> Void
    @ViewBuilder let content: (CGSize) -> Content

    @AppStorage("mycoder.webBrowserPanelHeight") private var height: Double = 280
    @State private var isResizing = false
    @State private var isHoveringHandle = false

    private var heightRange: ClosedRange<Double> { 180...700 }

    var body: some View {
        if isExpanded {
            expandedPanel
        } else {
            minimap
        }
    }

    // MARK: - Minimap (default)

    /// Small live thumbnail (232×150 + header). Hit testing on the page is
    /// off — any tap expands instead of poking tiny controls.
    private var minimap: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .foregroundColor(Color.mimo.cyan)
                Text(config.providerName)
                    .interfaceFont(size: 11, weight: .semibold)
                    .lineLimit(1)
                Spacer()
                Button(action: onExpand) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .interfaceFont(size: 10, weight: .medium)
                }
                .buttonStyle(HandCursorButtonStyle())
                .foregroundColor(Color.mimo.textMuted)
                .help("Expand the browser panel")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.mimo.border.opacity(0.6))

            GeometryReader { geo in
                content(geo.size)
                    .allowsHitTesting(false)
            }
            .frame(width: 232, height: 150)
            .background(Color.mimo.background)
            .clipped()
        }
        .frame(width: 232)
        .background(Color.mimo.border.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.mimo.cyan.opacity(0.5), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 2)
        .onTapGesture(perform: onExpand)
    }

    // MARK: - Expanded half-chat panel

    private var expandedPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .foregroundColor(Color.mimo.cyan)
                Text(config.providerName)
                    .interfaceFont(size: 12, weight: .semibold)
                    .lineLimit(1)
                Text("· \(chatLabel)")
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button(action: onCollapseToMini) {
                    Image(systemName: "chevron.down")
                        .interfaceFont(size: 11, weight: .medium)
                }
                .buttonStyle(HandCursorButtonStyle())
                .foregroundColor(Color.mimo.textMuted)
                .help("Collapse to minimap (the page stays alive)")
                Button(action: onHide) {
                    Image(systemName: "xmark")
                        .interfaceFont(size: 11, weight: .medium)
                }
                .buttonStyle(HandCursorButtonStyle())
                .foregroundColor(Color.mimo.textMuted)
                .help("Hide the browser panel (the page stays alive)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.mimo.border.opacity(0.6))

            GeometryReader { geo in
                content(geo.size)
            }
            .frame(height: height)
            .background(Color.mimo.background)
            .clipShape(RoundedCorners(radius: 4))

            // Drag handle to resize the panel: a wide hit area with a visible
            // grabber so the affordance is discoverable, not a hidden 4px strip.
            ZStack {
                Rectangle()
                    .fill(isResizing || isHoveringHandle ? Color.mimo.cyan.opacity(0.6) : Color.mimo.border)
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        Capsule()
                            .fill(Color.mimo.textMuted.opacity(isResizing || isHoveringHandle ? 0.9 : 0.5))
                            .frame(width: 2, height: 10)
                    }
                }
            }
            .frame(height: 12)
            .contentShape(Rectangle())
            .onHover { hovering in isHoveringHandle = hovering }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        isResizing = true
                        let proposed = height - value.translation.height
                        height = min(max(proposed, heightRange.lowerBound), heightRange.upperBound)
                    }
                    .onEnded { _ in isResizing = false }
            )
        }
        .background(Color.mimo.border.opacity(0.3))
        .clipShape(RoundedCorners(radius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.mimo.border, lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var chatLabel: String {
        config.chatID == "provider-default" ? "new chat" : String(config.chatID.prefix(8))
    }
}

/// Simple corner clipping (top corners only) used by the panel.
struct RoundedCorners: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(radius, rect.width / 2, rect.height / 2)
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r),
                    radius: r,
                    startAngle: .degrees(180),
                    endAngle: .degrees(270),
                    clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
                    radius: r,
                    startAngle: .degrees(270),
                    endAngle: .degrees(0),
                    clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
