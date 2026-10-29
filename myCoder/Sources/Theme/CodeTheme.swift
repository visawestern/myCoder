import SwiftUI

/// One syntax token produced by `CodeSyntaxHighlighter`.
enum CodeTokenKind: Equatable {
    case text
    case keyword
    case string
    case comment
    case number
    case function
    case type
    case constant
    case decorator
    case diffAdded
    case diffRemoved
    case diffMeta
}

/// Colour palette of a code block.
///
/// The Settings screen has always offered a light and a dark code theme, but
/// no renderer read the choice: every code block used the interface colours.
/// These palettes are the real values behind the names shown in Settings.
struct CodePalette: Equatable {
    let background: Color
    let headerBackground: Color
    let border: Color
    let text: Color
    let comment: Color
    let keyword: Color
    let string: Color
    let number: Color
    let function: Color
    let type: Color
    let constant: Color
    let decorator: Color
    let lineNumber: Color
    let diffAdded: Color
    let diffRemoved: Color
    let diffMeta: Color

    func color(for kind: CodeTokenKind) -> Color {
        switch kind {
        case .text: return text
        case .keyword: return keyword
        case .string: return string
        case .comment: return comment
        case .number: return number
        case .function: return function
        case .type: return type
        case .constant: return constant
        case .decorator: return decorator
        case .diffAdded: return diffAdded
        case .diffRemoved: return diffRemoved
        case .diffMeta: return diffMeta
        }
    }
}

/// Code themes offered by Settings → Code Preview.
enum CodeTheme: String, CaseIterable, Equatable {
    case githubLight = "GitHub Light"
    case githubDark = "GitHub Dark"
    case oneLight = "One Light"
    case oneDark = "One Dark"
    case solarizedLight = "Solarized Light"
    case solarizedDark = "Solarized Dark"
    case dracula = "Dracula"

    static func resolve(name: String, fallback: CodeTheme) -> CodeTheme {
        CodeTheme(rawValue: name) ?? fallback
    }

    var palette: CodePalette {
        switch self {
        case .githubLight:
            return .make(
                background: 0xFFFFFF, header: 0xF6F8FA, border: 0xD0D7DE, text: 0x24292F,
                comment: 0x6E7781, keyword: 0xCF222E, string: 0x0A3069, number: 0x0550AE,
                function: 0x8250DF, type: 0x953800, constant: 0x0550AE, decorator: 0xBF3989,
                lineNumber: 0x8C959F, diffAdded: 0x1A7F37, diffRemoved: 0xCF222E, diffMeta: 0x0969DA
            )
        case .githubDark:
            return .make(
                background: 0x0D1117, header: 0x161B22, border: 0x30363D, text: 0xC9D1D9,
                comment: 0x8B949E, keyword: 0xFF7B72, string: 0xA5D6FF, number: 0x79C0FF,
                function: 0xD2A8FF, type: 0xFFA657, constant: 0x79C0FF, decorator: 0xF778BA,
                lineNumber: 0x6E7681, diffAdded: 0x3FB950, diffRemoved: 0xF85149, diffMeta: 0x58A6FF
            )
        case .oneLight:
            return .make(
                background: 0xFAFAFA, header: 0xEAEAEB, border: 0xDBDBDC, text: 0x383A42,
                comment: 0xA0A1A7, keyword: 0xA626A4, string: 0x50A14F, number: 0x986801,
                function: 0x4078F2, type: 0xC18401, constant: 0x986801, decorator: 0xC18401,
                lineNumber: 0x9D9D9F, diffAdded: 0x50A14F, diffRemoved: 0xE45649, diffMeta: 0x4078F2
            )
        case .oneDark:
            return .make(
                background: 0x282C34, header: 0x21252B, border: 0x3E4451, text: 0xABB2BF,
                comment: 0x5C6370, keyword: 0xC678DD, string: 0x98C379, number: 0xD19A66,
                function: 0x61AFEF, type: 0xE5C07B, constant: 0xD19A66, decorator: 0x56B6C2,
                lineNumber: 0x636D83, diffAdded: 0x98C379, diffRemoved: 0xE06C75, diffMeta: 0x61AFEF
            )
        case .solarizedLight:
            return .make(
                background: 0xFDF6E3, header: 0xEEE8D5, border: 0xD9D2C2, text: 0x657B83,
                comment: 0x93A1A1, keyword: 0x859900, string: 0x2AA198, number: 0xD33682,
                function: 0x268BD2, type: 0xB58900, constant: 0xCB4B16, decorator: 0x6C71C4,
                lineNumber: 0x93A1A1, diffAdded: 0x859900, diffRemoved: 0xDC322F, diffMeta: 0x268BD2
            )
        case .solarizedDark:
            return .make(
                background: 0x002B36, header: 0x073642, border: 0x0E4A57, text: 0x839496,
                comment: 0x586E75, keyword: 0x859900, string: 0x2AA198, number: 0xD33682,
                function: 0x268BD2, type: 0xB58900, constant: 0xCB4B16, decorator: 0x6C71C4,
                lineNumber: 0x586E75, diffAdded: 0x859900, diffRemoved: 0xDC322F, diffMeta: 0x268BD2
            )
        case .dracula:
            return .make(
                background: 0x282A36, header: 0x21222C, border: 0x44475A, text: 0xF8F8F2,
                comment: 0x6272A4, keyword: 0xFF79C6, string: 0xF1FA8C, number: 0xBD93F9,
                function: 0x50FA7B, type: 0x8BE9FD, constant: 0xBD93F9, decorator: 0xFFB86C,
                lineNumber: 0x6272A4, diffAdded: 0x50FA7B, diffRemoved: 0xFF5555, diffMeta: 0x8BE9FD
            )
        }
    }
}

private extension CodePalette {
    static func make(
        background: UInt32,
        header: UInt32,
        border: UInt32,
        text: UInt32,
        comment: UInt32,
        keyword: UInt32,
        string: UInt32,
        number: UInt32,
        function: UInt32,
        type: UInt32,
        constant: UInt32,
        decorator: UInt32,
        lineNumber: UInt32,
        diffAdded: UInt32,
        diffRemoved: UInt32,
        diffMeta: UInt32
    ) -> CodePalette {
        CodePalette(
            background: Color(codeHex: background),
            headerBackground: Color(codeHex: header),
            border: Color(codeHex: border),
            text: Color(codeHex: text),
            comment: Color(codeHex: comment),
            keyword: Color(codeHex: keyword),
            string: Color(codeHex: string),
            number: Color(codeHex: number),
            function: Color(codeHex: function),
            type: Color(codeHex: type),
            constant: Color(codeHex: constant),
            decorator: Color(codeHex: decorator),
            lineNumber: Color(codeHex: lineNumber),
            diffAdded: Color(codeHex: diffAdded),
            diffRemoved: Color(codeHex: diffRemoved),
            diffMeta: Color(codeHex: diffMeta)
        )
    }
}

private extension Color {
    init(codeHex: UInt32) {
        self.init(
            .sRGB,
            red: Double((codeHex >> 16) & 0xFF) / 255,
            green: Double((codeHex >> 8) & 0xFF) / 255,
            blue: Double(codeHex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// Snapshot of the user's code-preview settings. Views read it from the
/// environment so nested renderers (message body, reasoning spoiler, spec
/// wizard) all use the same theme without threading `AppState` through.
struct CodeDisplaySettings: Equatable {
    var lightThemeName: String
    var darkThemeName: String
    var fontSize: Int
    var showLineNumbers: Bool
    var wrapLongLines: Bool

    init(
        lightThemeName: String = "GitHub Light",
        darkThemeName: String = "GitHub Dark",
        fontSize: Int = 12,
        showLineNumbers: Bool = true,
        wrapLongLines: Bool = true
    ) {
        self.lightThemeName = lightThemeName
        self.darkThemeName = darkThemeName
        self.fontSize = fontSize
        self.showLineNumbers = showLineNumbers
        self.wrapLongLines = wrapLongLines
    }

    init(settings: AppSettings) {
        self.init(
            lightThemeName: settings.lightCodeTheme,
            darkThemeName: settings.darkCodeTheme,
            fontSize: settings.codeFontSize,
            showLineNumbers: settings.showLineNumbers,
            wrapLongLines: settings.wrapLongLines
        )
    }

    static let `default` = CodeDisplaySettings()

    func theme(isLightInterface: Bool) -> CodeTheme {
        if isLightInterface {
            return CodeTheme.resolve(name: lightThemeName, fallback: .githubLight)
        }
        return CodeTheme.resolve(name: darkThemeName, fallback: .githubDark)
    }

    /// Settings allow 8…24; clamp defensively so a hand-edited settings file
    /// cannot produce an unreadable or zero-size block.
    var clampedFontSize: CGFloat {
        CGFloat(min(max(fontSize, 8), 24))
    }
}

private struct CodeDisplaySettingsKey: EnvironmentKey {
    static let defaultValue = CodeDisplaySettings.default
}

extension EnvironmentValues {
    var codeDisplaySettings: CodeDisplaySettings {
        get { self[CodeDisplaySettingsKey.self] }
        set { self[CodeDisplaySettingsKey.self] = newValue }
    }
}
