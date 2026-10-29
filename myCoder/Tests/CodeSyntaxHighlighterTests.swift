import Foundation
import Testing
@testable import myCoder

/// Chat code blocks used to be plain monospaced text: no Python keywords,
/// strings or comments were coloured and the palette chosen in Settings was
/// never read (user report 2026-10-29, chat «привет»).
@Suite("Подсветка синтаксиса в блоках кода")
struct CodeSyntaxHighlighterTests {

    private let pythonSample = """
    from astroquery.gaia import Gaia

    # первые 1000 звёзд
    def load(limit: int = 1000) -> str:
        query = "SELECT * FROM gaiadr3.gaia_source LIMIT %d" % limit
        return query
    """

    private func kind(
        of text: String,
        in tokens: [CodeToken]
    ) -> CodeTokenKind? {
        tokens.first { $0.text == text }?.kind
    }

    @Test("Токенизатор не теряет и не искажает исходный код")
    func tokensPreserveSource() {
        let tokens = CodeSyntaxHighlighter.tokenize(pythonSample, language: "python")
        #expect(tokens.map(\.text).joined() == pythonSample)
        #expect(!tokens.isEmpty)

        let attributed = CodeSyntaxHighlighter.attributed(
            pythonSample,
            language: "python",
            palette: CodeTheme.githubDark.palette
        )
        #expect(String(attributed.characters) == pythonSample)
    }

    @Test("Python: ключевые слова, функции, строки, числа и комментарии различаются")
    func pythonTokensAreClassified() {
        let tokens = CodeSyntaxHighlighter.tokenize(pythonSample, language: "py")
        #expect(kind(of: "from", in: tokens) == .keyword)
        #expect(kind(of: "import", in: tokens) == .keyword)
        #expect(kind(of: "def", in: tokens) == .keyword)
        #expect(kind(of: "return", in: tokens) == .keyword)
        #expect(kind(of: "load", in: tokens) == .function)
        #expect(kind(of: "int", in: tokens) == .function)
        #expect(kind(of: "str", in: tokens) == .function)
        #expect(kind(of: "\"SELECT * FROM gaiadr3.gaia_source LIMIT %d\"", in: tokens) == .string)
        #expect(kind(of: "# первые 1000 звёзд", in: tokens) == .comment)
        #expect(kind(of: "1000", in: tokens) == .number)
        #expect(kind(of: "Gaia", in: tokens) == .type)
    }

    @Test("Python-декоратор и triple-quoted строка распознаются")
    func pythonDecoratorAndTripleQuote() {
        let code = """
        @app.route("/health")
        def health():
            text = \"\"\"multi
        line\"\"\"
            return text
        """
        let tokens = CodeSyntaxHighlighter.tokenize(code, language: "python")
        #expect(tokens.map(\.text).joined() == code)
        #expect(kind(of: "@app.route", in: tokens) == .decorator)
        #expect(kind(of: "health", in: tokens) == .function)
        #expect(kind(of: "\"\"\"multi\nline\"\"\"", in: tokens) == .string)
    }

    @Test("Строки с escapes не выходят за свои кавычки")
    func escapedQuotesStayInString() {
        let code = #"let title = "say \"hi\" now""#
        let tokens = CodeSyntaxHighlighter.tokenize(code, language: "swift")
        #expect(tokens.map(\.text).joined() == code)
        #expect(kind(of: #""say \"hi\" now""#, in: tokens) == .string)
    }

    @Test("Swift: объявления и вызовы получают разные цвета")
    func swiftTokens() {
        let code = """
        struct Counter {
            func increment(by value: Int) -> Int {
                return value + 1
            }
        }
        """
        let tokens = CodeSyntaxHighlighter.tokenize(code, language: "swift")
        #expect(tokens.map(\.text).joined() == code)
        #expect(kind(of: "struct", in: tokens) == .keyword)
        #expect(kind(of: "Counter", in: tokens) == .type)
        #expect(kind(of: "increment", in: tokens) == .function)
        #expect(kind(of: "Int", in: tokens) == .function)
    }

    @Test("Diff-блок красит добавленные, удалённые и служебные строки")
    func diffTokens() {
        let code = """
        @@ -1 +1 @@
        -old line
        +new line
        plain
        """
        let tokens = CodeSyntaxHighlighter.tokenize(code, language: "diff")
        #expect(tokens.map(\.text).joined() == code)
        #expect(tokens.contains { $0.kind == .diffMeta && $0.text.hasPrefix("@@") })
        #expect(tokens.contains { $0.kind == .diffRemoved && $0.text == "-old line" })
        #expect(tokens.contains { $0.kind == .diffAdded && $0.text == "+new line" })
        #expect(tokens.contains { $0.kind == .text && $0.text == "plain" })
    }

    @Test("Diff определяется и без языка по маркерам строк")
    func diffDetection() {
        #expect(CodeSyntaxHighlighter.isDiff(code: "+a\n-b\n", language: "diff"))
        #expect(CodeSyntaxHighlighter.isDiff(code: "", language: "patch"))
        #expect(CodeSyntaxHighlighter.isDiff(
            code: "@@ -1,3 +1,3 @@\n+hello\n-goodbye\n",
            language: ""
        ))
        #expect(CodeSyntaxHighlighter.isDiff(
            code: "+++ b/file\n--- a/file\n",
            language: ""
        ))
        #expect(!CodeSyntaxHighlighter.isDiff(
            code: "let x = 1\nprint(x)\n",
            language: "swift"
        ))
        #expect(!CodeSyntaxHighlighter.isDiff(code: "plain text line\n", language: ""))
    }

    @Test("Пустой блок не даёт токенов")
    func emptyCodeHasNoTokens() {
        #expect(CodeSyntaxHighlighter.tokenize("", language: "python").isEmpty)
    }

    @Test("Bash: команда, комментарий и строка с URL различаются")
    func bashTokens() {
        let code = "# Скачаю CSV с элементами\ncurl -o elements.csv \"https://example.com/e.csv\"\n"
        let tokens = CodeSyntaxHighlighter.tokenize(code, language: "bash")
        #expect(tokens.map(\.text).joined() == code)
        #expect(kind(of: "# Скачаю CSV с элементами", in: tokens) == .comment)
        #expect(kind(of: "curl", in: tokens) == .function)
        #expect(kind(of: "\"https://example.com/e.csv\"", in: tokens) == .string)
    }
}
