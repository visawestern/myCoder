import SwiftUI

enum AppTheme: String, CaseIterable {
    case dark = "Dark"
    case lightGlass = "Sci-Fi Light"

    var preferredColorScheme: ColorScheme {
        switch self {
        case .dark: return .dark
        case .lightGlass: return .light
        }
    }
}

/// Design tokens for Sci-Fi Dark and Sci-Fi Light themes.
/// Contract: `surface` and `background` must differ on light theme; text tokens must meet contrast tests in `LightThemeContrastTests`.
extension Color {
    struct mimo {
        private static var currentTheme: AppTheme = {
            let raw = UserDefaults.standard.string(forKey: "com.mycoder.theme") ?? ""
            return AppTheme(rawValue: raw) ?? .dark
        }()
        
        static func setTheme(_ theme: AppTheme) {
            currentTheme = theme
            UserDefaults.standard.set(theme.rawValue, forKey: "com.mycoder.theme")
        }
        
        static var isLightTheme: Bool { currentTheme == .lightGlass }
        private static var isLight: Bool { isLightTheme }
        static var background: Color {
            isLight ? Color(red: 0.96, green: 0.98, blue: 1.0) : Color(red: 0.051, green: 0.067, blue: 0.09)
        }
        static var backgroundAlt: Color {
            isLight ? Color(red: 0.92, green: 0.95, blue: 0.99) : Color(red: 0.086, green: 0.106, blue: 0.133)
        }
        static var surface: Color {
            isLight ? Color(red: 0.99, green: 0.995, blue: 1.0) : Color(red: 0.129, green: 0.153, blue: 0.176)
        }
        static var surfaceHover: Color {
            isLight ? Color(red: 0.94, green: 0.96, blue: 0.99) : Color(red: 0.188, green: 0.212, blue: 0.239)
        }
        static var controlBackground: Color {
            isLight ? Color(red: 0.97, green: 0.98, blue: 1.0) : Color(red: 0.106, green: 0.125, blue: 0.149)
        }
        static var subtleFill: Color {
            isLight ? Color(red: 0.90, green: 0.93, blue: 0.97) : Color(red: 0.106, green: 0.125, blue: 0.149)
        }
        
        // Border
        static var border: Color {
            isLight ? Color(red: 0.62, green: 0.74, blue: 0.88) : Color(red: 0.188, green: 0.212, blue: 0.239)
        }
        static var borderHover: Color {
            isLight ? Color(red: 0.52, green: 0.66, blue: 0.84) : Color(red: 0.282, green: 0.306, blue: 0.345)
        }
        static var separator: Color {
            isLight ? Color(red: 0.68, green: 0.78, blue: 0.90) : Color(red: 0.22, green: 0.25, blue: 0.30)
        }
        
        // Brand
        static let brand = Color(red: 0.486, green: 0.227, blue: 0.929)
        static let brandDim = Color(red: 0.427, green: 0.157, blue: 0.851)
        
        // Accent - vibrant sci-fi colors
        static let cyan = Color(red: 0.0, green: 0.72, blue: 0.88)
        static let violet = Color(red: 0.45, green: 0.38, blue: 0.95)
        static let mint = Color(red: 0.20, green: 0.82, blue: 0.72)

        // Thinking / reasoning appears in the purple "thinking" tone.
        static let thinking = violet

        // Clickable inline links.
        static let link = Color(red: 0.20, green: 0.55, blue: 0.95)
        
        // Text - high contrast for light theme
        static var textPrimary: Color {
            isLight ? Color(red: 0.06, green: 0.10, blue: 0.18) : Color(red: 0.902, green: 0.933, blue: 0.953)
        }
        static var textSecondary: Color {
            isLight ? Color(red: 0.18, green: 0.28, blue: 0.42) : Color(red: 0.545, green: 0.58, blue: 0.62)
        }
        static var textMuted: Color {
            isLight ? Color(red: 0.28, green: 0.38, blue: 0.52) : Color(red: 0.431, green: 0.463, blue: 0.506)
        }
        
        // Status
        static let success = Color(red: 0.20, green: 0.82, blue: 0.72)
        static let warning = Color(red: 0.95, green: 0.55, blue: 0.25)
        static let error = Color(red: 0.95, green: 0.35, blue: 0.55)
        
        // Input
        static var input: Color {
            isLight ? Color(red: 0.955, green: 0.975, blue: 0.995) : Color(red: 0.051, green: 0.067, blue: 0.09)
        }
        static var inputBorder: Color {
            isLight ? Color(red: 0.58, green: 0.70, blue: 0.86) : Color(red: 0.188, green: 0.212, blue: 0.239)
        }
        static let inputBorderFocused = Color(red: 0.486, green: 0.227, blue: 0.929)
        
        // Code
        static var codeBg: Color {
            isLight ? Color(red: 0.88, green: 0.91, blue: 0.96) : Color(red: 0.051, green: 0.067, blue: 0.09)
        }
        static var codeHeaderBg: Color {
            isLight ? Color(red: 0.82, green: 0.86, blue: 0.92) : Color(red: 0.07, green: 0.085, blue: 0.11)
        }

        static var shadow: Color {
            isLight ? Color.black.opacity(0.12) : Color.black.opacity(0.2)
        }
    }
}

enum ThemeColorLuminance {
    enum Token {
        case input
        case background
        case surface
        case border
        case textPrimary
        case textMuted
        case codeBg
    }

    static func average(for token: Token, theme: AppTheme) -> Double {
        let rgb = rgbComponents(for: token, theme: theme)
        return relativeLuminance(r: rgb.0, g: rgb.1, b: rgb.2)
    }

    static func contrastRatio(foreground: Token, background: Token, theme: AppTheme) -> Double {
        let fg = average(for: foreground, theme: theme)
        let bg = average(for: background, theme: theme)
        let lighter = max(fg, bg)
        let darker = min(fg, bg)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func rgbComponents(for token: Token, theme: AppTheme) -> (Double, Double, Double) {
        switch (theme, token) {
        case (.lightGlass, .input): return (0.955, 0.975, 0.995)
        case (.lightGlass, .background): return (0.96, 0.98, 1.0)
        case (.lightGlass, .surface): return (0.99, 0.995, 1.0)
        case (.lightGlass, .border): return (0.62, 0.74, 0.88)
        case (.lightGlass, .textPrimary): return (0.06, 0.10, 0.18)
        case (.lightGlass, .textMuted): return (0.28, 0.38, 0.52)
        case (.lightGlass, .codeBg): return (0.88, 0.91, 0.96)
        case (.dark, .input): return (0.051, 0.067, 0.09)
        case (.dark, .background): return (0.051, 0.067, 0.09)
        case (.dark, .surface): return (0.129, 0.153, 0.176)
        case (.dark, .border): return (0.188, 0.212, 0.239)
        case (.dark, .textPrimary): return (0.902, 0.933, 0.953)
        case (.dark, .textMuted): return (0.431, 0.463, 0.506)
        case (.dark, .codeBg): return (0.051, 0.067, 0.09)
        }
    }

    private static func relativeLuminance(r: Double, g: Double, b: Double) -> Double {
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }
}
