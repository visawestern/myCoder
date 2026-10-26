import SwiftUI

private struct InterfaceFontScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var interfaceFontScale: CGFloat {
        get { self[InterfaceFontScaleKey.self] }
        set { self[InterfaceFontScaleKey.self] = newValue }
    }
}

enum InterfaceTypography {
    static func scaled(_ base: CGFloat, scale: CGFloat) -> CGFloat {
        (base * scale).rounded(.toNearestOrAwayFromZero)
    }

    static func font(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default, scale: CGFloat) -> Font {
        .system(size: scaled(size, scale: scale), weight: weight, design: design)
    }
}

struct InterfaceFontModifier: ViewModifier {
    @Environment(\.interfaceFontScale) private var scale
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(InterfaceTypography.font(size: size, weight: weight, design: design, scale: scale))
    }
}

extension View {
    func interfaceFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(InterfaceFontModifier(size: size, weight: weight, design: design))
    }
}

extension InputLayout {
    static func textMinHeight(scale: CGFloat) -> CGFloat {
        InterfaceTypography.scaled(textMinHeight, scale: scale)
    }

    static func textMaxHeight(scale: CGFloat) -> CGFloat {
        InterfaceTypography.scaled(textMaxHeight, scale: scale)
    }

    static func toolbarVerticalPadding(scale: CGFloat) -> CGFloat {
        InterfaceTypography.scaled(toolbarVerticalPadding, scale: scale)
    }

    static func toolbarHorizontalPadding(scale: CGFloat) -> CGFloat {
        InterfaceTypography.scaled(toolbarHorizontalPadding, scale: scale)
    }
}
