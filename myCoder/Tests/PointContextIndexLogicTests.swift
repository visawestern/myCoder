import Testing
import Foundation
@testable import myCoder

@Suite("Индекс для точечного контекста строится один раз, а не молча пустует")
struct PointContextIndexLogicTests {

    private func record(_ path: String) -> FileIndexRecord {
        FileIndexRecord(path: path, hash: "h", size: 10, lastModified: 1_700_000_000,
                        language: "swift", searchableText: "func store() {}")
    }

    @Test("Пустой индекс сканируется один раз и сохраняется")
    func emptyIndexIsScannedAndSaved() {
        var scanCount = 0
        var saved: [FileIndexRecord] = []
        let result = PointContextIndexLogic.records(
            projectPath: "/tmp/demo",
            load: { _ in [] },
            scan: { _ in
                scanCount += 1
                return [self.record("Sources/Store.swift")]
            },
            save: { path, records in
                #expect(path == "/tmp/demo")
                saved = records
            }
        )
        #expect(scanCount == 1)
        #expect(result.map(\.path) == ["Sources/Store.swift"])
        #expect(saved.map(\.path) == ["Sources/Store.swift"])
    }

    @Test("Готовый индекс не сканируется повторно")
    func storedIndexIsReused() {
        var scanCount = 0
        let result = PointContextIndexLogic.records(
            projectPath: "/tmp/demo",
            load: { _ in [self.record("Sources/Existing.swift")] },
            scan: { _ in
                scanCount += 1
                return [self.record("Sources/Other.swift")]
            },
            save: { _, _ in }
        )
        #expect(scanCount == 0)
        #expect(result.map(\.path) == ["Sources/Existing.swift"])
    }

    @Test("Пустой путь не сканирует и не сохраняет")
    func emptyPathIsNotScanned() {
        var scanCount = 0
        var saveCount = 0
        let result = PointContextIndexLogic.records(
            projectPath: "",
            load: { _ in [] },
            scan: { _ in scanCount += 1; return [] },
            save: { _, _ in saveCount += 1 }
        )
        #expect(result.isEmpty)
        #expect(scanCount == 0)
        #expect(saveCount == 0)
    }

    @Test("Проект без индексируемых файлов не сохраняет пустышку")
    func emptyScanIsNotSaved() {
        var saveCount = 0
        let result = PointContextIndexLogic.records(
            projectPath: "/tmp/empty",
            load: { _ in [] },
            scan: { _ in [] },
            save: { _, _ in saveCount += 1 }
        )
        #expect(result.isEmpty)
        #expect(saveCount == 0)
    }
}
