import SwiftUI

/// Small ring + percentage that shows how much of the model's context window
/// the current chat occupies (measured over the model-bound history, so it
/// drops immediately after `/compact`). Hovering reveals exact tokens.
struct ContextUsageBadge: View {
    let usage: ContextUsage

    private var tint: Color {
        if usage.ratio >= ContextUsageLogic.compactThreshold { return Color.mimo.error }
        if usage.ratio >= 0.75 { return Color.mimo.warning }
        return Color.mimo.cyan
    }

    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(Color.mimo.textMuted.opacity(0.22), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: max(0.02, usage.ratio))
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 12, height: 12)

            Text(ContextUsageLogic.badgeText(usage))
                .interfaceFont(size: 10)
                .foregroundColor(usage.ratio >= 0.75 ? tint : Color.mimo.textMuted)
        }
        .help(ContextUsageLogic.detailText(usage))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ContextUsageLogic.detailText(usage))
    }
}

/// Context ring placed in the input card's top-right corner. Hovering opens a
/// small dropdown with the exact context statistics (tokens used, window,
/// remaining, compact hint) instead of a plain tooltip.
struct ContextUsageIndicator: View {
    let usage: ContextUsage
    @State private var isHovered = false

    private var rows: [(String, String)] {
        [
            (L.t("Used"), ContextUsageLogic.formatTokens(usage.usedTokens)),
            (L.t("Window"), ContextUsageLogic.formatTokens(usage.limitTokens)),
            (L.t("Remaining"), ContextUsageLogic.formatTokens(usage.remainingTokens)),
            (L.t("Load"), "\(usage.percent)%"),
        ]
    }

    var body: some View {
        ContextUsageBadge(usage: usage)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(isHovered ? Color.mimo.surfaceHover : Color.clear)
            )
            .contentShape(Capsule())
            .popover(isPresented: $isHovered, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L.t("Context usage"))
                        .interfaceFont(size: 11, weight: .semibold)
                        .foregroundColor(Color.mimo.textPrimary)
                    ForEach(rows, id: \.0) { label, value in
                        HStack {
                            Text(label)
                                .interfaceFont(size: 11)
                                .foregroundColor(Color.mimo.textMuted)
                            Spacer(minLength: 12)
                            Text(value)
                                .interfaceFont(size: 11, weight: .medium)
                                .foregroundColor(Color.mimo.textPrimary)
                        }
                    }
                    if usage.percent >= Int(ContextUsageLogic.compactThreshold * 100) {
                        Divider()
                        Text("/compact")
                            .interfaceFont(size: 10, design: .monospaced)
                            .foregroundColor(Color.mimo.error)
                    }
                }
                .padding(10)
                .frame(width: 190)
            }
            .onHover { hovering in
                guard hovering != isHovered else { return }
                isHovered = hovering
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ContextUsageLogic.detailText(usage))
    }
}
