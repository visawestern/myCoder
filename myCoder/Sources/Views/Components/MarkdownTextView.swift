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
                    CodeBlockSpoilerView(language: language, code: code)

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

    /// Whether a code block should be rendered as a unified diff.
    /// Kept on `MarkdownText` because the renderer tests exercise it.
    static func isDiffBlock(_ code: String, language: String) -> Bool {
        CodeSyntaxHighlighter.isDiff(code: code, language: language)
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
