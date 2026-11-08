import Testing
import Foundation
@testable import myCoder

@Suite("Скриншоты — хранилище (общий путь меню и API)")
@MainActor
struct ScreenshotsStoreTests {

    @Test("Папка скриншотов лежит в домашней директории")
    func directoryLocation() {
        let home = URL(fileURLWithPath: "/Users/test")
        #expect(ScreenshotsStore.directory(homeDirectory: home).path == "/Users/test/myCoderScreenshots")
    }

    @Test("Список пустой папки — пустой массив (без записи в реальную домашнюю)")
    func emptyListIsEmpty() {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(ScreenshotsStore.list(homeDirectory: home).isEmpty)
    }

    @Test("ShotInfo сериализуется в словарь для API-ответа")
    func shotInfoDictionary() {
        let info = ScreenshotsStore.ShotInfo(
            path: "/tmp/shot.png", width: 100, height: 200,
            method: "cacheDisplay", windowTitle: "myCoder", bytes: 1234
        )
        let d = info.dictionary
        #expect(d["path"] as? String == "/tmp/shot.png")
        #expect(d["width"] as? Int == 100)
        #expect(d["height"] as? Int == 200)
        #expect(d["method"] as? String == "cacheDisplay")
        #expect(d["windowTitle"] as? String == "myCoder")
        #expect(d["bytes"] as? Int == 1234)
    }
}
