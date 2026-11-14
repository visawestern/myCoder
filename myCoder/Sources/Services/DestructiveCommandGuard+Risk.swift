import Foundation

/// How dangerous one shell command is. `safe` means the ordinary gate rules
/// apply; `destructive` means the user must confirm through the RED card even
/// at Full access (incident 2026-11-14: `rsync --delete` wiped a production
/// database and `migrate --force` recreated it empty, without a question).
enum CommandRisk: Equatable {
    case safe
    case destructive(reason: String)

    /// True when the command needs the explicit red confirmation.
    var isDestructive: Bool {
        if case .destructive = self { return true }
        return false
    }

    /// Human-readable reason shown in the approval card, or nil when safe.
    var reason: String? {
        if case .destructive(let reason) = self { return reason }
        return nil
    }
}

/// Classifies shell commands that destroy data or history. Pure functions:
/// input is the full command line, output is `CommandRisk`. The classifier
/// never executes anything and never depends on the machine state.
///
/// Covered families:
/// - recursive/wildcard file deletion (`rm -rf`, `rm *`, `find -delete`);
/// - mirror deletion (`rsync --delete*`);
/// - git history/discard commands (`push --force`, `reset --hard`, …);
/// - database drops/truncates/dump imports and migration resets;
/// - infrastructure destruction (`terraform destroy`, `kubectl delete`, …);
/// - in-place overwrites of database files (`> prod.db`, `dd of=…`).
extension DestructiveCommandGuard {

    /// Classifies one command line. Every subcommand of a chain is checked
    /// separately, after transparent wrappers (`sudo`, `env FOO=1`, `xargs`,
    /// `npx`, `nice -n 10`) are skipped.
    ///
    /// Вход: полная shell-команда.
    /// Выход: `.safe` или `.destructive(reason:)`.
    /// Зависимости: `ShellCommandScanner`.
    static func risk(for command: String) -> CommandRisk {
        let scan = ShellCommandScanner.scan(command)
        // Command substitutions run before the outer command: `echo $(rm -rf /)`
        // destroys data even though the outer command is `echo`.
        for inner in scan.substitutions {
            if case .destructive(let reason) = risk(for: inner) {
                return .destructive(reason: reason)
            }
        }
        for words in scan.subcommands where !words.isEmpty {
            let index = ShellCommandScanner.effectiveCommandIndex(in: words) ?? 0
            let name = words[index].lowercased()
            let args = Array(words[(index + 1)...])
            if let reason = reasonForCommand(name: name, args: args) {
                return .destructive(reason: reason)
            }
        }
        if scan.hasOutputRedirection,
           let target = databaseFileToken(in: scan.subcommands.flatMap { $0 }) {
            return .destructive(reason: "This command overwrites database file \(target) in place without a backup.")
        }
        return .safe
    }

    // MARK: - Reason texts

    private static let deletionReasonText =
        "Recursive or wildcard deletion can erase a whole directory tree without a backup."
    private static let overwriteReason =
        "This command overwrites a file in place without a backup."
    private static let rsyncReason =
        "`rsync --delete` deletes files on the destination that are missing from the source."
    private static let gitHistoryReason =
        "This git command rewrites or deletes history that cannot be restored."
    private static let gitDiscardReason =
        "This git command discards uncommitted changes permanently."
    private static let gitCleanReason =
        "`git clean -f` deletes untracked files permanently."
    private static let gitBranchReason =
        "`git branch -D` deletes a branch even if it is not merged."
    private static let gitStashReason =
        "`git stash drop/clear` deletes stashed changes permanently."
    private static let databaseWipeReason =
        "This database command drops, truncates or deletes data."
    private static let databaseImportReason =
        "Importing a SQL dump can overwrite the whole database."
    private static let migrationReason =
        "This migration resets or rebuilds the database and can erase all data."
    private static let infrastructureReason =
        "`terraform destroy` deletes managed infrastructure."
    private static let kubernetesReason =
        "This command deletes Kubernetes resources."
    private static let dockerReasonText =
        "This Docker command deletes volumes or all unused data."
    private static let awsReasonText =
        "This AWS command deletes S3 data or database resources."
    private static let herokuReasonText =
        "`heroku pg:reset` deletes the database."
    private static let firebaseReasonText =
        "This Firebase command deletes stored data."

    // MARK: - Dispatch

    /// Maps one canonical command + its arguments onto a destructive reason.
    ///
    /// Вход: имя команды (lowercase) и её аргументы.
    /// Выход: причина или nil.
    /// Зависимости: семейные функции ниже.
    private static func reasonForCommand(name: String, args: [String]) -> String? {
        switch name {
        case "rm": return deletionReason(args)
        case "find": return findDeletionReason(args)
        case "shred": return deletionReasonText
        case "truncate": return args.contains(where: { $0.hasPrefix("-s") }) ? overwriteReason : nil
        case "dd": return args.contains(where: { $0.hasPrefix("of=") }) ? overwriteReason : nil
        case "rsync": return rsyncDeletionReason(args)
        case "git": return gitReason(args)
        case "psql", "mysql", "mariadb", "sqlite3", "mongo", "mongosh", "redis-cli":
            return sqlReason(args)
        case "migrate": return args.contains("--force") ? migrationReason : nil
        case "php", "python", "python3": return scriptReason(name: name, args: args)
        case "prisma": return prismaReason(args)
        case "supabase": return joined(args).contains("db reset") ? migrationReason : nil
        case "rails", "rake": return railsReason(args)
        case "flyway": return verb(args) == "clean" ? migrationReason : nil
        case "liquibase": return joined(args).contains("drop-all") ? databaseWipeReason : nil
        case "sequelize": return args.contains(where: { $0.lowercased() == "db:drop" }) ? databaseWipeReason : nil
        case "knex": return knexReason(args)
        case "terraform": return terraformReason(args)
        case "kubectl": return verb(args) == "delete" ? kubernetesReason : nil
        case "helm": return ["uninstall", "delete"].contains(verb(args) ?? "") ? kubernetesReason : nil
        case "docker": return dockerReason(args)
        case "aws": return awsReason(args)
        case "gcloud": return args.contains(where: { $0.lowercased() == "delete" }) ? kubernetesReason : nil
        case "heroku": return herokuReason(args)
        case "firebase": return firebaseReason(args)
        case "bash", "sh", "zsh", "dash", "ksh", "fish":
            return shellScriptReason(args)
        case "eval":
            return riskReason(joined(args))
        case "ssh":
            return sshReason(args)
        case "bundle":
            // `bundle exec rails db:drop` — unwrap and classify the inner command.
            guard args.first?.lowercased() == "exec", args.count > 1 else { return nil }
            return reasonForCommand(name: args[1].lowercased(), args: Array(args.dropFirst(2)))
        default:
            return nil
        }
    }

    // MARK: - File deletion

    /// `rm` is destructive when it recurses or uses a wildcard. A plain
    /// `rm file.txt` stays ordinary (the prompt still requires a tmp backup
    /// for every deletion).
    ///
    /// Вход: аргументы rm. Выход: причина или nil. Зависимости: нет.
    private static func deletionReason(_ args: [String]) -> String? {
        let recursive = args.contains { token in
            token == "--recursive" || token == "-r" || token == "-R" || token == "-rf" || token == "-fr"
                || (token.hasPrefix("-") && !token.hasPrefix("--") && token.dropFirst().contains("r"))
        }
        let wildcard = args.contains { $0.contains("*") || $0.contains("?") }
        return (recursive || wildcard) ? deletionReasonText : nil
    }

    /// `find … -delete` and `find … -exec rm …` delete files.
    ///
    /// Вход: аргументы find. Выход: причина или nil. Зависимости: нет.
    private static func findDeletionReason(_ args: [String]) -> String? {
        if args.contains("-delete") { return deletionReasonText }
        let executes = args.contains("-exec") || args.contains("-execdir") || args.contains("-ok")
        let deletes = args.contains { $0 == "rm" || $0 == "shred" }
        return executes && deletes ? deletionReasonText : nil
    }

    /// `rsync --delete*` (and `--remove-source-files`) removes destination
    /// files that are missing at the source — the 2026-11-14 incident.
    ///
    /// Вход: аргументы rsync. Выход: причина или nil. Зависимости: нет.
    private static func rsyncDeletionReason(_ args: [String]) -> String? {
        let mirrors = args.contains { $0.hasPrefix("--delete") || $0 == "--remove-source-files" }
        return mirrors ? rsyncReason : nil
    }

    // MARK: - Git

    /// Destructive git subcommands: force push, hard reset, clean -f, branch
    /// -D, stash drop/clear, restore/checkout that discards changes, history
    /// rewriting.
    ///
    /// Вход: аргументы git (без самого слова git). Выход: причина или nil.
    /// Зависимости: `gitSubcommand`.
    private static func gitReason(_ args: [String]) -> String? {
        guard let (subcommand, rest) = gitSubcommand(args) else { return nil }
        switch subcommand {
        case "push":
            let force = rest.contains {
                $0 == "-f" || $0 == "--force" || $0.hasPrefix("--force-with-lease")
                    || $0 == "--mirror" || $0 == "--delete"
            }
            return force ? gitHistoryReason : nil
        case "reset":
            return rest.contains("--hard") ? gitDiscardReason : nil
        case "clean":
            let forced = rest.contains {
                $0 == "--force" || ($0.hasPrefix("-") && !$0.hasPrefix("--") && $0.contains("f"))
            }
            return forced ? gitCleanReason : nil
        case "branch":
            let deletes = rest.contains("-D") || (rest.contains("--delete") && rest.contains("--force"))
            return deletes ? gitBranchReason : nil
        case "stash":
            return ["drop", "clear"].contains(rest.first ?? "") ? gitStashReason : nil
        case "restore":
            return gitDiscardReason
        case "checkout":
            return rest.contains(".") || rest.contains("--") ? gitDiscardReason : nil
        case "filter-branch":
            return gitHistoryReason
        case "reflog":
            return rest.contains(where: { $0.hasPrefix("--expire=now") }) ? gitHistoryReason : nil
        case "gc":
            return rest.contains("--prune=now") ? gitHistoryReason : nil
        default:
            return nil
        }
    }

    /// Subcommand of `git`, skipping global flags that take a value
    /// (`git -C dir status`).
    ///
    /// Вход: аргументы git. Выход: (подкоманда, остальные аргументы).
    /// Зависимости: нет.
    private static func gitSubcommand(_ args: [String]) -> (String, [String])? {
        let valueFlags: Set<String> = ["-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"]
        var index = 0
        while index < args.count {
            let token = args[index]
            if valueFlags.contains(token) {
                index += 2
                continue
            }
            if token.hasPrefix("-") {
                index += 1
                continue
            }
            return (token.lowercased(), Array(args[(index + 1)...]))
        }
        return nil
    }

    // MARK: - Databases

    /// SQL text that drops, truncates, flushes or deletes/updates without a
    /// WHERE clause. Also catches dump imports via `< dump.sql`.
    ///
    /// Вход: аргументы клиента БД. Выход: причина или nil.
    /// Зависимости: нет.
    private static func sqlReason(_ args: [String]) -> String? {
        let text = joined(args)
        if text.contains("drop database") || text.contains("drop schema") || text.contains("drop table")
            || text.contains("truncate") || text.contains("flushall") || text.contains("flushdb")
            || text.contains("dropdb") {
            return databaseWipeReason
        }
        if let range = text.range(of: "delete from"), !text[range.upperBound...].contains(" where ") {
            return databaseWipeReason
        }
        if let range = text.range(of: "update "), text[range.upperBound...].contains(" set "),
           !text[range.upperBound...].contains(" where ") {
            return databaseWipeReason
        }
        if text.contains("<"), text.contains(".sql") || text.contains(".dump") {
            return databaseImportReason
        }
        return nil
    }

    /// `php artisan migrate --force|fresh|reset|refresh`, `db:wipe`,
    /// `python manage.py flush`.
    ///
    /// Вход: имя интерпретатора и аргументы. Выход: причина или nil.
    /// Зависимости: нет.
    private static func scriptReason(name: String, args: [String]) -> String? {
        let text = joined(args)
        if name == "php" {
            guard text.contains("artisan") else { return nil }
            if text.contains("db:wipe") { return databaseWipeReason }
            let resets = text.contains("--force") || text.contains("fresh")
                || text.contains("reset") || text.contains("refresh")
            return text.contains("migrate") && resets ? migrationReason : nil
        }
        if text.contains("manage.py"), text.contains("flush") {
            return databaseWipeReason
        }
        return nil
    }

    /// Prisma migration resets and `db push --force-reset`.
    ///
    /// Вход: аргументы prisma. Выход: причина или nil. Зависимости: нет.
    private static func prismaReason(_ args: [String]) -> String? {
        let text = joined(args)
        if text.contains("migrate"), text.contains("reset") || text.contains("--force") {
            return migrationReason
        }
        if text.contains("db push"), text.contains("--force-reset") {
            return databaseWipeReason
        }
        return nil
    }

    /// Rails/Rake database drops, resets and schema loads.
    ///
    /// Вход: аргументы rails/rake. Выход: причина или nil. Зависимости: нет.
    private static func railsReason(_ args: [String]) -> String? {
        let verbs = args.map { $0.lowercased() }
        if verbs.contains("db:drop") || verbs.contains("db:reset") || verbs.contains("db:wipe") {
            return databaseWipeReason
        }
        if verbs.contains("db:schema:load") || verbs.contains("db:migrate:reset") {
            return migrationReason
        }
        return nil
    }

    /// `knex migrate:rollback --all` wipes every applied migration.
    ///
    /// Вход: аргументы knex. Выход: причина или nil. Зависимости: нет.
    private static func knexReason(_ args: [String]) -> String? {
        let text = joined(args)
        return text.contains("migrate:rollback") && text.contains("--all") ? migrationReason : nil
    }

    // MARK: - Infrastructure

    /// `terraform destroy` and `terraform apply -destroy`.
    ///
    /// Вход: аргументы terraform. Выход: причина или nil. Зависимости: нет.
    private static func terraformReason(_ args: [String]) -> String? {
        let text = joined(args)
        return text.contains("destroy") ? infrastructureReason : nil
    }

    /// Docker volume/prune/system-wide deletions and `compose down -v`.
    ///
    /// Вход: аргументы docker. Выход: причина или nil. Зависимости: нет.
    private static func dockerReason(_ args: [String]) -> String? {
        let text = joined(args)
        if text.contains("system prune") || text.contains("volume rm") || text.contains("volume prune") {
            return dockerReasonText
        }
        let removesVolumes = args.contains("-v") || args.contains("--volumes")
        return text.contains("compose") && text.contains("down") && removesVolumes ? dockerReasonText : nil
    }

    /// S3 recursive/forced deletions and database resource deletions.
    ///
    /// Вход: аргументы aws. Выход: причина или nil. Зависимости: нет.
    private static func awsReason(_ args: [String]) -> String? {
        let text = joined(args)
        if text.contains("s3 rm"), text.contains("--recursive") || text.contains("*") {
            return awsReasonText
        }
        if text.contains("s3 rb"), text.contains("--force") { return awsReasonText }
        if text.contains("delete-db-instance") || text.contains("delete-table") { return awsReasonText }
        return nil
    }

    /// `heroku pg:reset` / `apps:destroy`.
    ///
    /// Вход: аргументы heroku. Выход: причина или nil. Зависимости: нет.
    private static func herokuReason(_ args: [String]) -> String? {
        let verbs = args.map { $0.lowercased() }
        return verbs.contains("pg:reset") || verbs.contains("apps:destroy") ? herokuReasonText : nil
    }

    /// Firebase data deletion (`firestore:delete`, `database:remove`).
    ///
    /// Вход: аргументы firebase. Выход: причина или nil. Зависимости: нет.
    private static func firebaseReason(_ args: [String]) -> String? {
        let text = joined(args)
        return text.contains(":delete") || text.contains(":remove") ? firebaseReasonText : nil
    }

    // MARK: - Shell wrappers and remote execution

    /// `bash -c '…'`, `zsh -lc '…'`, `sh -c "…"` — the script argument is a
    /// full command line and is classified recursively.
    ///
    /// Вход: аргументы оболочки. Выход: причина или nil.
    /// Зависимости: `riskReason`.
    private static func shellScriptReason(_ args: [String]) -> String? {
        for (offset, token) in args.enumerated() {
            guard token.hasPrefix("-"), !token.hasPrefix("--"),
                  token.contains("c") else { continue }
            guard offset + 1 < args.count else { return nil }
            return riskReason(args[offset + 1])
        }
        // `bash script.sh` cannot be classified without reading the script.
        return nil
    }

    /// `ssh [flags] host <remote command>` — the remote command is classified
    /// recursively so `ssh prod 'rm -rf /srv/app'` still asks for confirmation.
    ///
    /// Вход: аргументы ssh. Выход: причина или nil.
    /// Зависимости: `riskReason`.
    private static func sshReason(_ args: [String]) -> String? {
        let valueFlags: Set<String> = [
            "-p", "-i", "-l", "-o", "-F", "-J", "-L", "-R", "-D", "-W",
            "-b", "-c", "-E", "-e", "-m", "-S", "-w",
        ]
        var index = 0
        while index < args.count {
            let token = args[index]
            if valueFlags.contains(token) {
                index += 2
                continue
            }
            if token.hasPrefix("-") {
                index += 1
                continue
            }
            let remote = args[(index + 1)...].joined(separator: " ")
            return remote.isEmpty ? nil : riskReason(remote)
        }
        return nil
    }

    /// Reason of a nested command line, or nil when it is safe.
    ///
    /// Вход: вложенная команда. Выход: причина или nil.
    /// Зависимости: `risk`.
    private static func riskReason(_ command: String) -> String? {
        if case .destructive(let reason) = risk(for: command) { return reason }
        return nil
    }

    // MARK: - Helpers

    /// Lowercased arguments joined by spaces.
    ///
    /// Вход: аргументы. Выход: нормализованная строка. Зависимости: нет.
    private static func joined(_ args: [String]) -> String {
        args.map { $0.lowercased() }.joined(separator: " ")
    }

    /// First non-flag argument — the verb of tools like kubectl/helm/flyway.
    ///
    /// Вход: аргументы. Выход: глагол или nil. Зависимости: нет.
    private static func verb(_ args: [String]) -> String? {
        args.first { !$0.hasPrefix("-") }?.lowercased()
    }

    /// First token that looks like a database file (`.db`, `.sqlite`, …).
    ///
    /// Вход: токены команды. Выход: путь или nil. Зависимости: нет.
    private static func databaseFileToken(in tokens: [String]) -> String? {
        let suffixes = [".db", ".sqlite", ".sqlite3", ".dump", ".sql"]
        return tokens.first { token in
            let lower = token.lowercased()
            return suffixes.contains { lower.hasSuffix($0) }
        }
    }
}
