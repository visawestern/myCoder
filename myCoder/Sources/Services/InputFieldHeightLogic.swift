import CoreGraphics

enum InputFieldHeightLogic {
    static func lineCount(for text: String) -> Int {
        if text.isEmpty { return 1 }
        return text.components(separatedBy: "\n").count
    }

    static func preferredHeight(
        text: String,
        fontSize: CGFloat,
        minHeight: CGFloat,
        maxHeight: CGFloat,
        verticalPadding: CGFloat = 4
    ) -> CGFloat {
        let lines = lineCount(for: text)
        let lineHeight = fontSize * 1.25
        let content = CGFloat(lines) * lineHeight + verticalPadding
        return min(max(ceil(content), minHeight), maxHeight)
    }
}
