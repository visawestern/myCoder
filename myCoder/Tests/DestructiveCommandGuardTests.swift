import Foundation
import Testing
@testable import myCoder

/// TDD-набор для аудита A5: защита Full access от разрушительных команд.
/// `DestructiveCommandGuard.blockReason(for:)` возвращает причину блокировки
/// только для КРАЙНЕ разрушительных команд (удаление корня/home, форматирование
/// устройств, перезагрузка системы, fork-бомбы); обычные команды (включая
/// `rm -rf ./build` и `git reset --hard`) проходят.
@MainActor
@Suite("DestructiveCommandGuard (A5)")
struct DestructiveCommandGuardTests {

    private func expectBlocked(_ command: String, reasonContains: String) {
        let reason = DestructiveCommandGuard.blockReason(for: command)
        #expect(reason != nil, "должна быть блокировка для: \(command)")
        if let reason {
            #expect(reason.lowercased().contains(reasonContains.lowercased()),
                    "причина должна пояснять \(reasonContains): \(reason)")
        }
    }

    private func expectAllowed(_ command: String) {
        #expect(DestructiveCommandGuard.blockReason(for: command) == nil,
                "команда не должна блокироваться: \(command)")
    }

    @Test("Корневые удаления блокируются")
    func blocksRootDeletions() {
        expectBlocked("rm -rf /", reasonContains: "root")
        expectBlocked("rm -rf /*", reasonContains: "root")
        expectBlocked("sudo rm -rf /", reasonContains: "root")
        expectBlocked("rm -fr /", reasonContains: "root")
        expectBlocked("rm -r -f /", reasonContains: "root")
    }

    @Test("Удаление домашней/системной папки блокируется")
    func blocksHomeAndSystemDeletions() {
        expectBlocked("rm -rf ~", reasonContains: "home")
        expectBlocked("rm -rf $HOME", reasonContains: "home")
        expectBlocked("rm -rf /Users", reasonContains: "system")
        expectBlocked("rm -rf /System", reasonContains: "system")
        expectBlocked("rm -rf /private", reasonContains: "system")
    }

    @Test("Форматирование и перезапись устройств блокируются")
    func blocksDeviceWipes() {
        expectBlocked("mkfs.ext4 /dev/sda1", reasonContains: "format")
        expectBlocked("mkfs -t ext4 /dev/sda1", reasonContains: "format")
        expectBlocked("dd if=/dev/zero of=/dev/sda", reasonContains: "device")
        expectBlocked("dd if=/dev/zero of=/dev/rdisk0 bs=4m", reasonContains: "device")
        expectBlocked("diskutil eraseDisk JHFS+ X disk0", reasonContains: "disk")
        expectBlocked("diskutil secureErase 0 disk1", reasonContains: "disk")
    }

    @Test("Перезагрузка и выключение блокируются")
    func blocksSystemPowerCommands() {
        expectBlocked("shutdown now", reasonContains: "system")
        expectBlocked("reboot", reasonContains: "system")
        expectBlocked("halt", reasonContains: "system")
        expectBlocked("poweroff", reasonContains: "system")
    }

    @Test("Fork-бомбы блокируются")
    func blocksForkBombs() {
        expectBlocked(":(){ :|:& };:", reasonContains: "fork")
        expectBlocked(":(){ :|: & };:", reasonContains: "fork")
    }

    @Test("Обычные команды проходят")
    func allowsNormalCommands() {
        expectAllowed("echo hello")
        expectAllowed("ls -la")
        expectAllowed("npm test")
        expectAllowed("git status")
        expectAllowed("git diff")
        expectAllowed("git reset --hard HEAD")
        expectAllowed("rm file.txt")
        expectAllowed("rm -rf ./build")
        expectAllowed("rm -rf .build")
        expectAllowed("rm -rf /tmp/mycoder-tmp-xyz")
        expectAllowed("pkill -f 'myCoder'")
        expectAllowed("git commit -am 'fix: rm rf in code'")
    }
}
