import AppKit
import SwiftUI

/// Human-readable name for a fence language (`py` → `Python`).
enum CodeLanguageLabel {
    static func name(for raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "CODE" }
        switch trimmed.lowercased() {
        case "py", "python", "python3": return "Python"
        case "js", "javascript", "jsx", "node": return "JavaScript"
        case "ts", "typescript", "tsx": return "TypeScript"
        case "sh", "bash", "shell", "zsh", "console": return "Bash"
        case "json", "jsonc": return "JSON"
        case "sql", "mysql", "postgresql", "postgres", "sqlite": return "SQL"
        case "html", "htm", "xhtml": return "HTML"
        case "css", "scss", "sass", "less": return "CSS"
        case "swift": return "Swift"
        case "rs", "rust": return "Rust"
        case "go", "golang": return "Go"
        case "kt", "kotlin": return "Kotlin"
        case "md", "markdown": return "Markdown"
        case "yml", "yaml": return "YAML"
        case "diff", "patch": return "Diff"
        default: return trimmed.capitalized
        }
    }
}

/// Fenced code block rendered as a spoiler: language header with a copy
/// button, collapsible body, real syntax colours from the theme chosen in
/// Settings → Code Preview, code font size, line numbers and wrap behaviour.
///
/// The chat previously painted code inside the plain text view, so none of
/// those settings reached it and a Python block looked like highlighted
/// prose. Prose stays in `SelectableMarkdownTextView`; fences become this
/// view (see `MarkdownCodeSegmentLogic`).
struct CodeBlockSpoilerView: View {
    let language: String
    let code: String

    @Environment(\.codeDisplaySettings) private var settings
    @State private var isExpanded: Bool
    @State private var copied = false

    init(language: String, code: String, startsExpanded: Bool = true) {
        self.language = language
        self.code = code
        _isExpanded = State(initialValue: startsExpanded)
    }

    private var palette: CodePalette {
        settings.theme(isLightInterface: Color.mimo.isLightTheme).palette
    }

    private var codeFont: Font {
        .system(size: settings.clampedFontSize, design: .monospaced)
    }

    private var highlighted: AttributedString {
        CodeSyntaxHighlighter.attributed(code, language: language, palette: palette)
    }

    private var lineCount: Int {
        max(1, code.components(separatedBy: "\n").count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                codeBody
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.background)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(palette.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .animation(SpoilerExpandLogic.animation, value: isExpanded)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(SpoilerExpandLogic.animation) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 10)
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 10))
                    Text(CodeLanguageLabel.name(for: language))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                }
                .foregroundColor(palette.text.opacity(0.8))
                .contentShape(Rectangle())
            }
            .buttonStyle(HandCursorButtonStyle())

            Spacer(minLength: 0)

            Text("\(lineCount) \(L.t(AppLocalizationKey.locLines))")
                .font(.system(size: 10))
                .foregroundColor(palette.lineNumber)
                .lineLimit(1)

            Button(action: copyCode) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(copied ? Color.mimo.success : palette.text.opacity(0.7))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HandCursorButtonStyle())
            .help(copied ? L.t(AppLocalizationKey.locCopied) : L.t(AppLocalizationKey.locCopy))
            .accessibilityLabel(L.t(AppLocalizationKey.locCopy))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(palette.headerBackground)
    }

    @ViewBuilder
    private var codeBody: some View {
        if settings.showLineNumbers {
            // Line numbers only line up with logical lines, so a numbered
            // block scrolls horizontally instead of soft-wrapping.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    gutter
                    Rectangle()
                        .fill(palette.border.opacity(0.6))
                        .frame(width: 1)
                    codeText
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.leading, 10)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }
        } else if settings.wrapLongLines {
            codeText
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                codeText
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(10)
            }
        }
    }

    private var codeText: some View {
        Text(highlighted)
            .font(codeFont)
            .textSelection(.enabled)
    }

    private var gutter: some View {
        Text((1...lineCount).map(String.init).joined(separator: "\n"))
            .font(codeFont)
            .foregroundColor(palette.lineNumber)
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.trailing, 8)
    }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { copied = false }
        }
    }
}
