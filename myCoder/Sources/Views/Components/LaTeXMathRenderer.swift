import Foundation

/// Lightweight LaTeX-to-Unicode renderer for model markdown output.
///
/// Gemma-family models liberally sprinkle chat answers with `$…$`, `$$…$$`,
/// `\(...\)` and `\[…\]` math. myCoder does not embed a TeX engine; instead
/// this renderer rewrites frequent LaTeX constructs into readable Unicode
/// (superscripts, subscripts, fractions, roots, greek operators) so math stays
/// legible inside a plain `NSTextView`/`Text`.
enum LaTeXMathRenderer {
    static func render(_ latex: String) -> String {
        var result = latex

        result = stripMatrixEnvironments(result)
        result = preStripDelimiters(result)
        result = regexReplace(result, pattern: #"\\frac\s*\{([^{}]*)\}\s*\{([^{}]*)\}"#) { groups in
            "\(groups.first ?? "a")/\(groups.count > 1 ? groups[1] : "b")"
        }
        result = regexReplace(result, pattern: #"\\sqrt\{((?:[^{}]|\{[^{}]*\})+)\}"#) { groups in
            "√(\(groups.first ?? ""))"
        }
        result = replaceSuperscripts(result)
        result = replaceSubscripts(result)
        for (latex, unicode) in LaTeXMathSymbols.replacements {
            result = result.replacingOccurrences(of: latex, with: unicode)
        }
        result = replaceOperators(result)
        result = cleanupResidue(result)

        return result
    }

    /// Delimiters and layout spacing must vanish before symbol mapping runs,
    /// otherwise `\left` degrades into `\le` → `≤ft`. Each command is stripped
    /// only when it is the complete command (`\left` must not touch
    /// `\leftarrow`), and drops without spaces.
    private static func preStripDelimiters(_ s: String) -> String {
        var result = s
        for command in ["displaystyle", "left", "right", "!", ",", ";", "(", ")", "[", "]"] {
            let pattern = "\\\\" + NSRegularExpression.escapedPattern(for: command) + "(?![a-zA-Z])"
            result = LaTeXMathRenderer.regexReplace(result, pattern: pattern) { _ in "" }
        }
        return result
    }

    /// True when a `$…$` candidate is really math, not two independent
    /// dollar amounts in a sentence ("cost $5 and $10 total").
    static func looksLikeMath(_ inner: String) -> Bool {
        inner.contains(where: { $0 == "\\" })
            || inner.range(of: #"[^\\][\^_]"#, options: .regularExpression) != nil
    }

    /// Extracts the body of `\(...\)` or `\[…\]` math delimiters.
    static func delimitedBody(_ s: String) -> String? {
        guard s.hasPrefix("\\(") && s.hasSuffix("\\)") && s.count >= 2 else { return nil }
        return String(s.dropFirst(2).dropLast(2))
            .trimmingCharacters(in: .whitespaces)
    }

    /// Regex replace that resolves capture groups via `transform`, avoiding
    /// catastrophic re-scanning on content the transform itself created.
    static func regexReplace(_ s: String,
                             pattern: String,
                             transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
        let ns = s as NSString
        var result = ""
        var lastLocation = 0
        for match in regex.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            let range = match.range
            guard range.location != NSNotFound else { continue }
            let prefixLength = range.location - lastLocation
            if prefixLength > 0 {
                result += ns.substring(with: NSRange(location: lastLocation, length: prefixLength))
            }
            var groups: [String] = []
            for i in 1..<match.numberOfRanges {
                let groupRange = match.range(at: i)
                if groupRange.location != NSNotFound,
                   groupRange.location + groupRange.length <= ns.length {
                    groups.append(ns.substring(with: groupRange))
                } else {
                    groups.append("")
                }
            }
            result += transform(groups)
            lastLocation = range.location + range.length
        }
        if lastLocation < ns.length {
            result += ns.substring(from: lastLocation)
        }
        return result
    }

    private static func stripMatrixEnvironments(_ s: String) -> String {
        var result = s
        for env in ["pmatrix", "bmatrix", "vmatrix", "Bmatrix", "matrix", "cases", "aligned", "align", "array"] {
            result = result.replacingOccurrences(of: "\\begin{\(env)}", with: "⎡ ")
            result = result.replacingOccurrences(of: "\\end{\(env)}", with: " ⎤")
        }
        // Row separator \\ reads as a stacked-line break.
        result = result.replacingOccurrences(of: " \\\\", with: " ⋮ ")
        result = result.replacingOccurrences(of: "\\\\ ", with: " ⋮ ")
        result = result.replacingOccurrences(of: "\\\\", with: " ⋮ ")
        // Column separator & becomes a visual gap.
        result = result.replacingOccurrences(of: " & ", with: "   ")
        return result
    }

    private static func replaceSuperscripts(_ s: String) -> String {
        var result = regexReplace(s, pattern: #"\^\{([^{}]+)\}"#) { groups in
            unicodeScript(groups.joined(), map: LaTeXMathSymbols.superscripts, fallback: "ˆ")
        }
        result = regexReplace(result, pattern: #"\^([0-9n+\-−])"#) { groups in
            unicodeScript(groups.joined(), map: LaTeXMathSymbols.superscripts, fallback: "ˆ")
        }
        return result
    }

    private static func replaceSubscripts(_ s: String) -> String {
        var result = regexReplace(s, pattern: #"_\{([^{}]+)\}"#) { groups in
            unicodeScript(groups.joined(), map: LaTeXMathSymbols.subscripts, fallback: "")
        }
        result = regexReplace(result, pattern: #"_([0-9n+\-−])"#) { groups in
            unicodeScript(groups.joined(), map: LaTeXMathSymbols.subscripts, fallback: "")
        }
        return result
    }

    private static func unicodeScript(_ inner: String,
                                      map: [Character: Character],
                                      fallback: String) -> String {
        guard !inner.isEmpty else { return fallback }
        var mapped = ""
        for ch in inner {
            guard let replacement = map[ch] else { return "^(\(inner))".replacingOccurrences(of: "^", with: fallback) }
            mapped.append(replacement)
        }
        return mapped
    }

    private static func replaceOperators(_ s: String) -> String {
        var result = s
        result = result.replacingOccurrences(of: "\\cdot", with: "·")
        result = result.replacingOccurrences(of: "\\times", with: "×")
        result = result.replacingOccurrences(of: "\\div", with: "÷")
        result = result.replacingOccurrences(of: "\\pm", with: "±")
        result = result.replacingOccurrences(of: "\\mp", with: "∓")
        return result
    }

    private static func cleanupResidue(_ s: String) -> String {
        var result = regexReplace(s, pattern: #"\{([^{}]*)\}"#) { groups in
            groups.first ?? ""
        }
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}

/// Unicode glyph tables for LaTeX math rendering.
enum LaTeXMathSymbols {
    static let greekAndOperators: [String: String] = [
        "\\alpha": "α", "\\beta": "β", "\\gamma": "γ", "\\delta": "δ",
        "\\epsilon": "ε", "\\varepsilon": "ε", "\\zeta": "ζ", "\\eta": "η",
        "\\theta": "θ", "\\vartheta": "ϑ", "\\iota": "ι", "\\kappa": "κ",
        "\\lambda": "λ", "\\mu": "μ", "\\nu": "ν", "\\xi": "ξ", "\\pi": "π",
        "\\rho": "ρ", "\\sigma": "σ", "\\tau": "τ", "\\upsilon": "υ",
        "\\phi": "φ", "\\varphi": "φ", "\\chi": "χ", "\\psi": "ψ",
        "\\omega": "ω", "\\Gamma": "Γ", "\\Delta": "Δ", "\\Theta": "Θ",
        "\\Lambda": "Λ", "\\Xi": "Ξ", "\\Pi": "Π", "\\Sigma": "Σ",
        "\\Phi": "Φ", "\\Psi": "Ψ", "\\Omega": "Ω",
        "\\rightarrow": "→", "\\leftarrow": "←", "\\Rightarrow": "⇒",
        "\\Leftarrow": "⇐", "\\leftrightarrow": "↔", "\\Leftrightarrow": "⇔",
        "\\implies": "⇒", "\\to": "→", "\\gets": "←", "\\infty": "∞",
        "\\sum": "∑", "\\prod": "∏", "\\int": "∫", "\\oint": "∮",
        "\\nabla": "∇", "\\partial": "∂", "\\approx": "≈",
        "\\neq": "≠", "\\ne": "≠", "\\le": "≤", "\\leq": "≤", "\\ge": "≥",
        "\\geq": "≥", "\\equiv": "≡", "\\sim": "∼", "\\propto": "∝",
        "\\in": "∈", "\\notin": "∉", "\\ni": "∋", "\\subset": "⊂",
        "\\subseteq": "⊆", "\\supset": "⊃", "\\supseteq": "⊇",
        "\\cup": "∪", "\\cap": "∩", "\\emptyset": "∅", "\\varnothing": "∅",
        "\\forall": "∀", "\\exists": "∃", "\\neg": "¬", "\\land": "∧",
        "\\lor": "∨", "\\oplus": "⊕", "\\otimes": "⊗", "\\perp": "⊥",
        "\\parallel": "∥", "\\angle": "∠", "\\deg": "°", "\\prime": "′",
        "\\vdots": "⋮", "\\star": "⋆", "\\circ": "∘", "\\bullet": "•",
        "\\ell": "ℓ", "\\Re": "ℜ", "\\Im": "ℑ", "\\hbar": "ℏ", "\\wp": "℘",
        "\\lim": "lim", "\\max": "max", "\\min": "min", "\\det": "det",
        "\\dim": "dim", "\\exp": "exp", "\\log": "log", "\\ln": "ln",
        "\\sgn": "sgn", "\\sinh": "sinh", "\\cosh": "cosh", "\\tanh": "tanh"
    ]

    /// Longest keys first so `\leftarrow` never loses `\left` or `\le`.
    static let replacements: [(String, String)] = greekAndOperators
        .map { ($0.key, $0.value) }
        .sorted { lhs, rhs in
            if lhs.0.count != rhs.0.count { return lhs.0.count > rhs.0.count }
            return lhs.0 < rhs.0
        }

    static let superscripts: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵",
        "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "+": "⁺", "-": "⁻",
        "−": "⁻", "n": "ⁿ", "(": "⁽", ")": "⁾", "=": "⁼"
    ]

    static let subscripts: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅",
        "6": "₆", "7": "₇", "8": "₈", "9": "₉", "+": "₊", "-": "₋",
        "−": "₋", "n": "ₙ", "(": "₍", ")": "₎", "=": "₌"
    ]
}
