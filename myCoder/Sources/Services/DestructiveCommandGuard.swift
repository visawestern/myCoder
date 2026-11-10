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

        if tokens.contains("/") || tokens.contains("/*") {
            return "Deleting the filesystem root is blocked (destructive command)."
        }
        if tokens.contains("~") || tokens.contains("$home") {
            return "Deleting the home directory is blocked (destructive command)."
        }
        let systemRoots = ["/users", "/system", "/private", "/home"]
        if let matched = tokens.first(where: { systemRoots.contains($0) }) {
            return "Deleting system directory \(matched) is blocked (destructive command)."
        }
        return nil
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
