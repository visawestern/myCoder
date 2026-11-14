import Foundation

/// Result of splitting one shell command line into independently executable
/// subcommands.
struct ShellCommandScan: Equatable {
    /// One element per command. `cd api && rm -rf x` yields two entries.
    let subcommands: [[String]]
    /// True when the line redirects stdout/stderr (`>`, `>>`, `2>`). Such a
    /// command writes to the filesystem and is never read-only.
    let hasOutputRedirection: Bool
    /// Bodies of command substitutions (`$(…)` and backticks). Each one is a
    /// full command that runs BEFORE the outer command, so both the read-only
    /// allowlist and the destructive classifier must inspect them.
    let substitutions: [String]
}

/// Quote-aware shell command scanner shared by the read-only allowlist
/// (`WebToolAccessGate`) and the destructive-command classifier
/// (`DestructiveCommandGuard.risk`). One parser means both checks agree on
/// what actually runs: `echo "rm -rf /"` is a single `echo`, while
/// `cd api && rsync --delete …` is two commands.
enum ShellCommandScanner {

    /// Wrappers that only execute the command that follows them. The real
    /// command starts after these words (and their flags/assignments).
    private static let transparentPrefixes: Set<String> = [
        "sudo", "doas", "env", "time", "nice", "xargs", "npx", "bunx",
    ]

    /// Flags that consume the next token as their value. Needed so
    /// `nice -n 10 rm …` and `env -u NAME rm …` still find `rm`.
    private static let flagsWithValue: Set<String> = [
        "-n", "-u", "-I", "-P", "-L", "-s", "--max-args", "--max-procs",
        "--delimiter", "--replace", "--user", "--group",
    ]

    /// Splits `command` into subcommands, respecting single quotes, double
    /// quotes and backticks. Quotes themselves are dropped from tokens so
    /// flags like `sed -i` are still recognised. Command substitutions
    /// (`$(…)`, backticks) are collected separately — they execute before the
    /// outer command and must be classified too.
    ///
    /// Вход: полная командная строка.
    /// Выход: подкоманды + признак перенаправления + подстановки.
    /// Зависимости: нет (чистый разбор строки).
    static func scan(_ command: String) -> ShellCommandScan {
        let chars = Array(command)
        var index = 0
        var inQuote: Character?
        var current = ""
        var words: [String] = []
        var subcommands: [[String]] = []
        var substitutions: [String] = []
        var hasOutputRedirection = false

        func flushWord() {
            let trimmed = current.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { words.append(trimmed) }
            current = ""
        }
        func flushSubcommand() {
            flushWord()
            if !words.isEmpty {
                subcommands.append(words)
                words = []
            }
        }

        /// Reads the body of `$(…)`; `index` points at `$`. Nested
        /// parentheses are balanced, quotes inside are respected.
        func readDollarParen() -> String {
            var depth = 1
            var inner = ""
            var innerQuote: Character?
            index += 2
            while index < chars.count {
                let ch = chars[index]
                if let quote = innerQuote {
                    if ch == quote { innerQuote = nil }
                    inner.append(ch)
                    index += 1
                    continue
                }
                if ch == "'" || ch == "\"" {
                    innerQuote = ch
                    inner.append(ch)
                    index += 1
                    continue
                }
                if ch == "(" { depth += 1 }
                if ch == ")" {
                    depth -= 1
                    if depth == 0 {
                        index += 1
                        break
                    }
                }
                inner.append(ch)
                index += 1
            }
            return inner
        }

        /// Reads the body of a backtick substitution.
        func readBacktick() -> String {
            var inner = ""
            index += 1
            while index < chars.count, chars[index] != "`" {
                inner.append(chars[index])
                index += 1
            }
            if index < chars.count { index += 1 }   // closing backtick
            return inner
        }

        while index < chars.count {
            let ch = chars[index]
            if let quote = inQuote {
                // Single quotes are literal; double quotes still execute
                // substitutions.
                if ch == quote {
                    inQuote = nil
                    index += 1
                    continue
                }
                if quote == "\"", ch == "$", index + 1 < chars.count,
                   chars[index + 1] == "(" {
                    let inner = readDollarParen()
                    substitutions.append(inner)
                    current.append("$(\(inner))")
                    continue
                }
                if quote == "\"", ch == "`" {
                    let inner = readBacktick()
                    substitutions.append(inner)
                    current.append("$(\(inner))")
                    continue
                }
                current.append(ch)
                index += 1
                continue
            }
            if ch == "'" || ch == "\"" {
                inQuote = ch
                index += 1
                continue
            }
            if ch == "`" {
                let inner = readBacktick()
                substitutions.append(inner)
                current.append("$(\(inner))")
                continue
            }
            if ch == "$", index + 1 < chars.count, chars[index + 1] == "(" {
                let inner = readDollarParen()
                substitutions.append(inner)
                current.append("$(\(inner))")
                continue
            }
            if ch == ">" {
                hasOutputRedirection = true
                index += 1
                continue
            }
            if ch == "&" || ch == ";" || ch == "|" || ch == "\n" {
                flushSubcommand()
                index += 1
                continue
            }
            if ch == " " || ch == "\t" {
                flushWord()
                index += 1
                continue
            }
            current.append(ch)
            index += 1
        }
        flushSubcommand()

        return ShellCommandScan(
            subcommands: subcommands,
            hasOutputRedirection: hasOutputRedirection,
            substitutions: substitutions
        )
    }

    /// Index of the command that actually runs after transparent prefixes:
    /// `sudo rm …` → 1, `env FOO=1 rm …` → 2, `nice -n 10 rm …` → 3,
    /// `xargs -0 rm …` → 2, `npx prisma …` → 1.
    ///
    /// Вход: токены одной подкоманды.
    /// Выход: индекс реальной команды или nil, если команды нет (голый
    /// `xargs` по умолчанию запускает `echo`).
    /// Зависимости: нет.
    static func effectiveCommandIndex(in words: [String]) -> Int? {
        var index = 0
        while index < words.count, transparentPrefixes.contains(words[index].lowercased()) {
            let prefix = words[index].lowercased()
            index += 1
            while index < words.count {
                let token = words[index]
                if token.hasPrefix("-") {
                    index += flagsWithValue.contains(token) ? 2 : 1
                    continue
                }
                // `env FOO=1 cmd` — assignments are not the command.
                if prefix == "env", token.contains("="), !token.hasPrefix("/") {
                    index += 1
                    continue
                }
                break
            }
        }
        return index < words.count ? index : nil
    }
}
