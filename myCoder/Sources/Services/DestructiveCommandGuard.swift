import Foundation

/// Защита от крайне разрушительных shell-команд (audit A5). Full access
/// разрешал исполнять `rm -rf /`, форматирование дисков, перезагрузку и
/// fork-бомбы без каких-либо преград. Этот guard — чистая функция: по команде
/// возвращает причину блокировки или nil. Он блокирует только КАТАСТРОФИЧЕСКИЕ
/// паттерны; обычные команды (включая `rm -rf ./build`, `git reset --hard`,
/// `pkill`) проходят без изменений.
enum DestructiveCommandGuard {

    /// Проверяет команду на разрушительные паттерны.
    ///
    /// Вход: полная shell-команда. Выход: RU-причина блокировки или nil.
    /// Зависимости: нет (чистая эвристика по нормализованным токенам).
    static func blockReason(for command: String) -> String? {
        let tokens = normalizedTokens(command)

        if let reason = rootDeletionReason(tokens) { return reason }
        if let reason = deviceWipeReason(tokens) { return reason }
        if let reason = systemPowerReason(tokens) { return reason }
        if let reason = forkBombReason(command) { return reason }
        return nil
    }

    /// Нормализует команду: lowercase, коллапс пробелов, снятие sudo/doas/env.
    ///
    /// Вход: команда. Выход: массив токенов.
    /// Зависимости: нет.
    private static func normalizedTokens(_ command: String) -> [String] {
        var value = command.lowercased()
        value = value.replacingOccurrences(of: "\n", with: " ")
        value = value.split(separator: " ").joined(separator: " ")
        var changed = true
        while changed {
            changed = false
            for prefix in ["sudo ", "doas ", "env "] {
                if value.hasPrefix(prefix) {
                    value = String(value.dropFirst(prefix.count))
                    changed = true
                }
            }
        }
        return value.split(separator: " ").map(String.init)
    }

    /// Блокирует удаление корня, домашней или системной папки через
    /// `rm -rf`/`rm -fr`/`rm -r -f` (+ `--recursive --force`).
    ///
    /// Вход: токены команды. Выход: причина или nil.
    /// Зависимости: нет.
    private static func rootDeletionReason(_ tokens: [String]) -> String? {
        guard tokens.contains("rm") else { return nil }
        let recursive = tokens.contains("-rf") || tokens.contains("-fr")
            || (tokens.contains("-r") && tokens.contains("-f"))
            || (tokens.contains("--recursive") && tokens.contains("--force"))
        guard recursive else { return nil }

        // `cd / && rm -rf *` не содержит токена `/` рядом с rm, но удаляет
        // всё содержимое корня. Проверяем цель перехода и маску удаления.
        if let chdirIndex = tokens.firstIndex(of: "cd"),
           tokens.count > chdirIndex + 1 {
            let target = cleanToken(tokens[chdirIndex + 1])
            let deletesEverything = tokens.contains("*") || tokens.contains("./*")
                || tokens.contains("*.") || tokens.contains("/*")
            if deletesEverything {
                if target == "/" || target == "//" { return rootReason }
                if isSystemPath(target) {
                    return "Deleting system directory \(target) is blocked (destructive command)."
                }
            }
        }

        for token in tokens {
            let value = cleanToken(token)
            if value == "/" || value == "/*" || value == "//" {
                return rootReason
            }
            if isHomePath(value) {
                return "Deleting the home directory is blocked (destructive command)."
            }
            if isSystemPath(value) {
                return "Deleting system directory \(value) is blocked (destructive command)."
            }
        }
        return nil
    }

    private static let rootReason = "Deleting the filesystem root is blocked (destructive command)."

    /// Системные корни: удаление самого корня или любого пути внутри него
    /// необратимо ломает машину. `/tmp` и пользовательские временные папки
    /// сознательно не входят в список.
    private static let systemRoots = [
        "/users", "/system", "/library", "/applications", "/etc",
        "/usr", "/bin", "/sbin", "/opt", "/cores", "/volumes", "/home"
    ]

    /// Снимает обрамляющие кавычки и знаки командной строки, чтобы
    /// `rm -rf "/Users/x";` распознавался так же, как `rm -rf /Users/x`.
    ///
    /// Вход: токен. Выход: очищенный токен. Зависимости: нет.
    private static func cleanToken(_ token: String) -> String {
        token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`()[]{};,"))
    }

    /// Домашний каталог: `~`, `~/…`, `~user`, `$HOME`, `${HOME}/…`.
    ///
    /// Вход: токен. Выход: true, если путь ведёт в домашний каталог.
    /// Зависимости: нет.
    private static func isHomePath(_ value: String) -> Bool {
        if value.hasPrefix("~") { return true }
        if value == "$home" || value.hasPrefix("$home/") { return true }
        if value.hasPrefix("${home}") { return true }
        return false
    }

    /// Путь внутри системного корня. `/private/tmp` и
    /// `/private/var/folders` — временные каталоги, их удаление не ломает
    /// систему, поэтому они исключены.
    ///
    /// Вход: токен. Выход: true для системного пути. Зависимости: нет.
    private static func isSystemPath(_ value: String) -> Bool {
        if value.hasPrefix("/private") {
            if value.hasPrefix("/private/tmp") || value.hasPrefix("/private/var/folders") {
                return false
            }
            return value == "/private" || value.hasPrefix("/private/")
        }
        for root in systemRoots {
            if value == root || value.hasPrefix(root + "/") { return true }
        }
        return false
    }

    /// Блокирует форматирование (mkfs/diskutil) и перезапись блочных устройств
    /// (dd … of=/dev/…).
    ///
    /// Вход: токены команды. Выход: причина или nil.
    /// Зависимости: нет.
    private static func deviceWipeReason(_ tokens: [String]) -> String? {
        if tokens.contains(where: { $0.hasPrefix("mkfs") }) {
            return "Formatting a disk is blocked (destructive command)."
        }
        if tokens.contains(where: { $0.hasPrefix("diskutil") }),
           tokens.contains(where: { $0.lowercased().contains("erase") }) {
            return "Erasing a disk is blocked (destructive command)."
        }
        if tokens.contains("dd"), tokens.contains(where: { $0.hasPrefix("of=/dev/") }) {
            return "Overwriting a device is blocked (destructive command)."
        }
        return nil
    }

    /// Блокирует перезагрузку/выключение системы.
    ///
    /// Вход: токены команды. Выход: причина или nil.
    /// Зависимости: нет.
    private static func systemPowerReason(_ tokens: [String]) -> String? {
        let powerTokens = ["shutdown", "reboot", "halt", "poweroff"]
        if tokens.contains(where: { powerTokens.contains($0) }) {
            return "System reboot/shutdown is blocked (destructive command)."
        }
        return nil
    }

    /// Блокирует fork-бомбы вида `:(){ :|:& };:`.
    ///
    /// Вход: исходная команда (в токенах паттерн разрушается). Выход: причина.
    /// Зависимости: нет.
    private static func forkBombReason(_ command: String) -> String? {
        let lower = command.lowercased()
        if lower.contains(":(){") || lower.contains(":|:") {
            return "Fork bomb is blocked (destructive command)."
        }
        return nil
    }
}
