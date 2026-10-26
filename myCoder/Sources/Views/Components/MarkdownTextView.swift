import SwiftUI

struct MarkdownText: View {
    @Environment(\.interfaceFontScale) private var interfaceFontScale
    let text: String
    var fontSize: CGFloat = 14
    var textColor: Color = Color.mimo.textPrimary

    private var scaledFontSize: CGFloat {
        InterfaceTypography.scaled(fontSize, scale: interfaceFontScale)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parseMarkdown().enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let content):
                    Text(content)
                        .font(.system(size: headingSize(level), weight: .bold))
                        .foregroundColor(textColor)
                        .padding(.top, level == 1 ? 4 : 2)

                case .codeBlock(let language, let code):
                    VStack(alignment: .leading, spacing: 0) {
                        CodeBlockHeader(language: language, code: code)
                        MarkdownText.highlightedCode(code, language: language,
                                                     baseColor: textColor,
                                                     fontSize: max(10, scaledFontSize - 1))
                            .textSelection(.enabled)
                            .padding(10)
                    }
                    .background(Color.mimo.codeBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                case .inlineCode(let code):
                    Text(code)
                        .font(.system(size: max(10, scaledFontSize - 1), design: .monospaced))
                        .foregroundColor(Color.mimo.brand)
                        .padding(.horizontal, 4)
                        .background(Color.mimo.brand.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                case .bold(let content):
                    Text(content)
                        .font(.system(size: scaledFontSize, weight: .bold))
                        .foregroundColor(textColor)

                case .bulletItem(let content):
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                            .foregroundColor(Color.mimo.textMuted)
                        MarkdownInline(text: content, fontSize: scaledFontSize, textColor: textColor)
                    }

                case .numberedItem(let number, let content):
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(number).")
                            .font(.system(size: scaledFontSize, weight: .medium))
                            .foregroundColor(Color.mimo.thinking)
                            .frame(width: max(16, scaledFontSize + 6), alignment: .trailing)
                        MarkdownInline(text: content, fontSize: scaledFontSize, textColor: textColor)
                    }

                case .blockquote(let content):
                    HStack(alignment: .top, spacing: 8) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.mimo.brand.opacity(0.4))
                            .frame(width: 3)
                        MarkdownInline(text: content, fontSize: scaledFontSize, textColor: textColor)
                            .foregroundColor(Color.mimo.textMuted)
                    }
                    .padding(.leading, 4)

                case .checkbox(let isChecked, let content):
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                            .interfaceFont(size: scaledFontSize)
                            .foregroundColor(isChecked ? Color.mimo.thinking : Color.mimo.textMuted)
                            .frame(width: max(16, scaledFontSize + 4), alignment: .center)
                        MarkdownInline(text: content, fontSize: scaledFontSize, textColor: textColor)
                    }

                case .horizontalRule:
                    Rectangle()
                        .fill(Color.mimo.border)
                        .frame(height: 1)
                        .padding(.vertical, 4)

                case .table(let rows):
                    tableBlock(rows)

                case .paragraph(let content):
                    MarkdownInline(text: content, fontSize: scaledFontSize, textColor: textColor)

                case .math(let latex):
                    Text(LaTeXMathRenderer.render(latex))
                        .font(.system(size: scaledFontSize, design: .monospaced))
                        .foregroundColor(textColor)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 2)
                        .background(Color.mimo.brand.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .textSelection(.enabled)
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return scaledFontSize + 4
        case 2: return scaledFontSize + 2
        default: return scaledFontSize
        }
    }

    private func languageColor(_ lang: String) -> Color {
        MarkdownText.codeLanguageColor(lang)
    }

    static func codeLanguageColor(_ lang: String) -> Color {
        switch lang.lowercased() {
        case "swift": return Color(red: 0.94, green: 0.32, blue: 0.22)
        case "python", "py": return Color(red: 0.22, green: 0.47, blue: 0.67)
        case "javascript", "js": return Color(red: 1.0, green: 0.85, blue: 0.24)
        case "typescript", "ts": return Color(red: 0.19, green: 0.47, blue: 0.78)
        case "html", "htm": return Color(red: 1.0, green: 0.42, blue: 0.42)
        case "css": return Color(red: 0.29, green: 0.80, blue: 0.77)
        case "rust": return Color(red: 0.75, green: 0.35, blue: 0.22)
        case "go": return Color(red: 0.0, green: 0.74, blue: 0.84)
        default: return Color.mimo.textMuted
        }
    }

    /// Render a code block with light syntax highlighting (K) and diff (+/-/@@)
    /// line coloring (C). Keeps the same monospaced font; only colors change.
    static func highlightedCode(_ code: String, language: String,
                                baseColor: Color, fontSize: CGFloat) -> Text {
        let mono = Font.system(size: fontSize, design: .monospaced)
        let lower = language.lowercased()
        let diffMode = isDiffBlock(code, language: lower)
        let keywords = keywords(for: lower)
        var result = Text("")
        let lines = code.components(separatedBy: "\n")
        for (idx, line) in lines.enumerated() {
            if idx > 0 { result = result + Text("\n") }
            let piece = diffMode ? diffLine(line, baseColor: baseColor)
                                 : tokenizeLine(line, keywords: keywords, baseColor: baseColor)
            result = result + piece
        }
        return result.font(mono)
    }

    /// Whether a code block should be rendered as a unified diff (colors the
    /// +/-/@@ prefixes). True for `diff`/`patch` fenced blocks or any block
    /// whose lines carry diff markers.
    static func isDiffBlock(_ code: String, language: String) -> Bool {
        let lower = language.lowercased()
        if lower == "diff" || lower == "patch" { return true }
        return code.components(separatedBy: "\n").contains { l in
            l.hasPrefix("+++") || l.hasPrefix("---") || l.hasPrefix("@@")
                || l.hasPrefix("diff --git") || l.hasPrefix("index ")
        }
    }

    private static func diffLine(_ line: String, baseColor: Color) -> Text {
        if line.hasPrefix("+++") || line.hasPrefix("---")
            || line.hasPrefix("diff ") || line.hasPrefix("index ")
            || line.hasPrefix("new file") || line.hasPrefix("deleted file")
            || line.hasPrefix("similarity") || line.hasPrefix("rename") {
            return Text(line).foregroundColor(Color.mimo.cyan)
        }
        if line.hasPrefix("@@") {
            return Text(line).foregroundColor(Color.mimo.thinking)
        }
        if line.hasPrefix("+") {
            return Text(line).foregroundColor(Color.mimo.mint)
        }
        if line.hasPrefix("-") {
            return Text(line).foregroundColor(Color.mimo.error)
        }
        return Text(line).foregroundColor(baseColor)
    }

    /// Very light tokenizer: strings, line comments, numbers and known keywords
    /// get a color; everything else stays in the base color.
    private static func tokenizeLine(_ line: String, keywords: Set<String>,
                                     baseColor: Color) -> Text {
        let kwColor = Color.mimo.thinking
        let strColor = Color.mimo.mint
        let numColor = Color.mimo.cyan
        let comColor = Color.mimo.textMuted
        let pattern = #"("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`[^`]*`)|(//[^\n]*|#[^\n]*)|(\b\d+(?:\.\d+)?\b)|(\b[A-Za-z_][A-Za-z0-9_]*\b)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              !line.isEmpty else {
            return Text(line).foregroundColor(baseColor)
        }
        let ns = line as NSString
        let matches = regex.matches(in: line, range: NSRange(location: 0, length: ns.length))
        var result = Text("")
        var pos = 0
        for m in matches {
            let mRange = m.range(at: 0)
            if mRange.location > pos {
                let gap = ns.substring(with: NSRange(location: pos, length: mRange.location - pos))
                result = result + Text(gap).foregroundColor(baseColor)
            }
            let text = ns.substring(with: mRange)
            let color: Color
            if m.range(at: 1).location != NSNotFound {
                color = strColor
            } else if m.range(at: 2).location != NSNotFound {
                color = comColor
            } else if m.range(at: 3).location != NSNotFound {
                color = numColor
            } else {
                color = keywords.contains(text) ? kwColor : baseColor
            }
            result = result + Text(text).foregroundColor(color)
            pos = mRange.location + mRange.length
        }
        if pos < ns.length {
            result = result + Text(ns.substring(with: NSRange(location: pos, length: ns.length - pos)))
                .foregroundColor(baseColor)
        }
        return result
    }

    private static func keywords(for language: String) -> Set<String> {
        let base: Set<String> = [
            "let", "var", "func", "return", "if", "else", "for", "while", "in",
            "class", "struct", "enum", "extension", "import", "guard", "switch",
            "case", "break", "continue", "nil", "true", "false", "self", "static",
            "public", "private", "internal", "override", "new", "void", "int",
            "string", "bool", "double", "float", "const", "def", "async", "await",
            "try", "catch", "throw", "throws",
        ]
        let lower = language.lowercased()
        if lower.contains("python") || lower.contains("py") {
            return base.union(["print", "lambda", "None", "with", "as", "elif",
                               "yield", "from", "raise", "del", "global", "not"])
        }
        if lower.contains("js") || lower.contains("ts")
            || lower.contains("javascript") || lower.contains("typescript") {
            return base.union(["function", "export", "default", "=>"])
        }
        if lower == "json" || lower == "yaml" || lower == "yml" || lower == "toml" {
            return []
        }
        return base
    }

    /// Block kinds of a markdown document. The parsing itself lives in
    /// `MarkdownDocumentParser` so the rich renderer and the single-surface
    /// selectable renderer always agree on the document structure.
    typealias Block = MarkdownBlock

    func parseMarkdown() -> [Block] {
        MarkdownDocumentParser.parse(text)
    }

    @ViewBuilder
    private func tableBlock(_ rows: [[String]]) -> some View {
        if let header = rows.first, rows.count > 1 {
            let columnCount = max(header.count, rows[1...].map(\.count).max() ?? header.count)
            let bodyRows = Array(rows.dropFirst())

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(0..<max(columnCount, 1), id: \.self) { col in
                        tableCell(header, col: col, isHeader: true)
                    }
                }
                .background(Color.mimo.codeHeaderBg)

                ForEach(Array(bodyRows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 0) {
                        ForEach(0..<max(columnCount, 1), id: \.self) { col in
                            tableCell(row, col: col, isHeader: false)
                        }
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.mimo.border.opacity(0.6), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private func tableCell(_ row: [String], col: Int, isHeader: Bool) -> some View {
        let value = col < row.count ? row[col] : ""
        HStack(alignment: .top, spacing: 0) {
            if isHeader {
                Text(value)
                    .font(.system(size: scaledFontSize - 1, weight: .semibold))
                    .foregroundColor(textColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
            } else {
                MarkdownInline(text: value, fontSize: scaledFontSize - 1, textColor: textColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
        }
        .background(
            col % 2 == 1 ? Color.mimo.codeBg.opacity(0.5) : Color.clear
        )
        .overlay(
            Rectangle()
                .fill(Color.mimo.border.opacity(0.5))
                .frame(width: col == 0 ? 0 : 1),
            alignment: .leading
        )
    }
}

struct CodeBlockHeader: View {
    let language: String
    let code: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: 6) {
            Text(language.isEmpty ? "CODE" : language.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(MarkdownText.codeLanguageColor(language))
                .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
                withAnimation { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation { copied = false }
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(
                        copied ? Color.mimo.success : Color.mimo.textMuted
                    )
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HandCursorButtonStyle())
            .help(copied ? L.t(AppLocalizationKey.locCopied) : L.t(AppLocalizationKey.locCopyAll))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.mimo.codeHeaderBg)
    }
}

struct MarkdownInline: View {
    let text: String
    var fontSize: CGFloat = 14
    var textColor: Color = Color.mimo.textPrimary

    var body: some View {
        let parts = parseInline(text)
        FlowLayout(parts: parts, fontSize: fontSize, textColor: textColor)
    }

    /// Inline fragment kinds. Parsing lives in `MarkdownInlineParser`.
    typealias InlinePart = MarkdownInlineToken

    func parseInline(_ s: String) -> [InlinePart] {
        MarkdownInlineParser.parse(s)
    }
}

struct FlowLayout: View {
    let parts: [MarkdownInline.InlinePart]
    var fontSize: CGFloat = 14
    var textColor: Color = Color.mimo.textPrimary

    var body: some View {
        parts.reduce(Text("")) { result, part in
            switch part {
            case .text(let t):
                return result + Text(t).foregroundColor(textColor)
            case .bold(let t):
                return result + Text(t).bold().foregroundColor(textColor)
            case .italic(let t):
                return result + Text(t).italic().foregroundColor(textColor)
            case .code(let t):
                return result + Text(" \(t) ")
                    .font(.system(size: max(10, fontSize - 1), design: .monospaced))
                    .foregroundColor(Color.mimo.brand)
            case .link(let title, let url):
                return result + Text("[\(title)](\(url))")
                    .underline()
                    .foregroundColor(Color.mimo.link)
            case .mathInline(let latex):
                return result + Text(latex).italic().foregroundColor(textColor)
            }
        }
        .font(.system(size: fontSize))
    }
}
