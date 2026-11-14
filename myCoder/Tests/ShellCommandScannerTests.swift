import Foundation
import Testing
@testable import myCoder

/// TDD для общего разборщика shell-команд. И белый список read-only команд,
/// и классификатор деструктивности обязаны делить командную строку одинаково:
/// `echo "rm -rf /"` — это не `rm`, а `cd api && rsync --delete ...` — две
/// отдельные команды, каждая со своей проверкой.
@MainActor
@Suite("Shell command scanner")
struct ShellCommandScannerTests {

    @Test("Цепочки команд делятся на подкоманды")
    func splitsCommandChains() {
        #expect(ShellCommandScanner.scan("cd api && rsync -a --delete ./ prod:/srv/").subcommands == [
            ["cd", "api"],
            ["rsync", "-a", "--delete", "./", "prod:/srv/"],
        ])
        #expect(ShellCommandScanner.scan("a; b | c || d").subcommands == [
            ["a"], ["b"], ["c"], ["d"],
        ])
        #expect(ShellCommandScanner.scan("a\nb").subcommands == [["a"], ["b"]])
    }

    @Test("Кавычки защищают содержимое от разбиения")
    func quotesProtectContent() {
        let scan = ShellCommandScanner.scan("echo 'a && b'")
        #expect(scan.subcommands == [["echo", "a && b"]])
    }

    @Test("Перенаправление вывода распознаётся, но не внутри кавычек")
    func detectsOutputRedirection() {
        #expect(ShellCommandScanner.scan("echo hi > out.txt").hasOutputRedirection)
        #expect(ShellCommandScanner.scan("echo hi 2> err.txt").hasOutputRedirection)
        #expect(!ShellCommandScanner.scan("echo 'a > b'").hasOutputRedirection)
    }

    @Test("Кавычки не оставляют следов в токенах")
    func quotesAreDroppedFromTokens() {
        #expect(ShellCommandScanner.scan("echo 'a b'").subcommands == [["echo", "a b"]])
        #expect(ShellCommandScanner.scan("mysql -e \"DELETE FROM users\"").subcommands
            == [["mysql", "-e", "DELETE FROM users"]])
    }

    @Test("Подстановки команд собираются, в том числе внутри двойных кавычек")
    func collectsCommandSubstitutions() {
        #expect(ShellCommandScanner.scan("echo $(date)").substitutions == ["date"])
        #expect(ShellCommandScanner.scan("echo \"$(date)\"").substitutions == ["date"])
        #expect(ShellCommandScanner.scan("echo `date`").substitutions == ["date"])
        #expect(ShellCommandScanner.scan("echo \"`date`\"").substitutions == ["date"])
        #expect(ShellCommandScanner.scan("echo '$(date)'").substitutions.isEmpty)
        #expect(ShellCommandScanner.scan("echo $(echo $(date))").substitutions == ["echo $(date)"])
        #expect(ShellCommandScanner.scan("echo plain").substitutions.isEmpty)
    }

    @Test("Прозрачные префиксы пропускаются до реальной команды")
    func skipsTransparentPrefixes() {
        #expect(ShellCommandScanner.effectiveCommandIndex(in: ["sudo", "rm", "-rf", "x"]) == 1)
        #expect(ShellCommandScanner.effectiveCommandIndex(in: ["env", "FOO=1", "rm", "-rf", "x"]) == 2)
        #expect(ShellCommandScanner.effectiveCommandIndex(in: ["time", "npm", "test"]) == 1)
        #expect(ShellCommandScanner.effectiveCommandIndex(in: ["nice", "-n", "10", "rm", "x"]) == 3)
        #expect(ShellCommandScanner.effectiveCommandIndex(in: ["xargs", "-0", "rm", "-rf"]) == 2)
        #expect(ShellCommandScanner.effectiveCommandIndex(in: ["xargs"]) == nil)
        #expect(ShellCommandScanner.effectiveCommandIndex(in: ["git", "status"]) == 0)
    }
}
