import SwiftUI

struct SciFiCornerBrackets: View {
    let color: Color
    private let arm: CGFloat = 11

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack {
                cornerPath(x: 0, y: 0, flipX: false, flipY: false)
                cornerPath(x: width, y: 0, flipX: true, flipY: false)
                cornerPath(x: 0, y: height, flipX: false, flipY: true)
                cornerPath(x: width, y: height, flipX: true, flipY: true)
            }
        }
        .allowsHitTesting(false)
    }

    private func cornerPath(x: CGFloat, y: CGFloat, flipX: Bool, flipY: Bool) -> some View {
        Path { path in
            let dx: CGFloat = flipX ? -1 : 1
            let dy: CGFloat = flipY ? -1 : 1
            path.move(to: CGPoint(x: x + dx * arm, y: y))
            path.addLine(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x, y: y + dy * arm))
        }
        .stroke(color, lineWidth: 1.5)
    }
}

struct SciFiScanlines: View {
    let opacity: Double

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                var y: CGFloat = 0
                while y < size.height {
                    let rect = CGRect(x: 0, y: y, width: size.width, height: 1)
                    context.fill(Path(rect), with: .color(.white.opacity(opacity)))
                    y += 4
                }
            }
        }
    }
}

struct SciFiPrimaryButton: View {
    let title: String
    let enabled: Bool
    let theme: PlanQuestionWizardTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .interfaceFont(size: 11, weight: .bold, design: .monospaced)
                .tracking(0.8)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    LinearGradient(
                        colors: enabled ? theme.primaryButtonFill : [Color.mimo.textMuted.opacity(0.35)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(enabled ? 0.18 : 0), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: enabled ? theme.glowColor : .clear, radius: 8)
        }
        .buttonStyle(HandCursorButtonStyle())
        .disabled(!enabled)
    }
}

struct SciFiWizardPanel<Content: View>: View {
    let theme: PlanQuestionWizardTheme
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(14)
            .background(
                LinearGradient(colors: theme.panelGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .overlay(SciFiCornerBrackets(color: theme.accent.opacity(0.85)))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        LinearGradient(colors: theme.borderGradient, startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1.2
                    )
            )
            .overlay(
                SciFiScanlines(opacity: theme.scanlineOpacity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .allowsHitTesting(false)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: theme.glowColor, radius: 14, y: 2)
    }
}

struct PlanQuestionWizardTheme {
    let panelGradient: [Color]
    let borderGradient: [Color]
    let glowColor: Color
    let accent: Color
    let accentSecondary: Color
    let headerTitle: String
    let progressTrack: Color
    let optionFill: Color
    let optionSelectedFill: Color
    let optionBorder: Color
    let optionSelectedBorder: Color
    let primaryButtonFill: [Color]
    let secondaryButtonFill: Color
    let scanlineOpacity: Double

    static var current: PlanQuestionWizardTheme {
        Color.mimo.isLightTheme ? light : dark
    }

    static let dark = PlanQuestionWizardTheme(
        panelGradient: [
            Color(red: 0.04, green: 0.07, blue: 0.14),
            Color(red: 0.07, green: 0.10, blue: 0.20)
        ],
        borderGradient: [Color.mimo.cyan.opacity(0.85), Color.mimo.brand.opacity(0.9)],
        glowColor: Color.mimo.cyan.opacity(0.35),
        accent: Color.mimo.cyan,
        accentSecondary: Color.mimo.violet,
        headerTitle: "INPUT REQUIRED",
        progressTrack: Color.white.opacity(0.08),
        optionFill: Color.white.opacity(0.04),
        optionSelectedFill: Color.mimo.cyan.opacity(0.14),
        optionBorder: Color.mimo.cyan.opacity(0.22),
        optionSelectedBorder: Color.mimo.cyan.opacity(0.75),
        primaryButtonFill: [Color.mimo.cyan, Color.mimo.brand],
        secondaryButtonFill: Color.white.opacity(0.06),
        scanlineOpacity: 0.05
    )

    static let light = PlanQuestionWizardTheme(
        panelGradient: [
            Color(red: 0.94, green: 0.97, blue: 1.0),
            Color(red: 0.88, green: 0.93, blue: 0.99)
        ],
        borderGradient: [Color.mimo.brand.opacity(0.75), Color.mimo.cyan.opacity(0.85)],
        glowColor: Color.mimo.brand.opacity(0.22),
        accent: Color.mimo.brand,
        accentSecondary: Color.mimo.cyan,
        headerTitle: "INPUT REQUIRED",
        progressTrack: Color.mimo.border.opacity(0.35),
        optionFill: Color.white.opacity(0.72),
        optionSelectedFill: Color.mimo.brand.opacity(0.12),
        optionBorder: Color.mimo.border.opacity(0.65),
        optionSelectedBorder: Color.mimo.brand.opacity(0.65),
        primaryButtonFill: [Color.mimo.brand, Color.mimo.cyan.opacity(0.85)],
        secondaryButtonFill: Color.white.opacity(0.85),
        scanlineOpacity: 0.04
    )
}
