import Testing
import Foundation
@testable import myCoder

/// User directive 2026-11-03 (п.2): while the context is being assembled, the
/// composer shows ONE line saying exactly what is happening right now and what
/// is being collected — not a generic "собирается контекст".
@MainActor
@Suite("Однострочный лог сборки контекста")
struct ContextStageLogTests {

    @Test("Каждая стадия даёт непустую однострочную подпись")
    func everyStageHasOneLine() {
        for stage in ContextStageLogLogic.Stage.allCases {
            let line = ContextStageLogLogic.line(for: stage)
            #expect(!line.isEmpty)
            #expect(!line.contains("\n"))
        }
    }

    @Test("Подпись называет источник, который читается на этой стадии")
    func lineNamesTheSource() {
        #expect(ContextStageLogLogic.line(for: .index).lowercased().contains("индекс"))
        #expect(ContextStageLogLogic.line(for: .memory).lowercased().contains("память"))
        #expect(ContextStageLogLogic.line(for: .graph).lowercased().contains("граф"))
        #expect(ContextStageLogLogic.line(for: .skills).lowercased().contains("скилл"))
        #expect(ContextStageLogLogic.line(for: .files).lowercased().contains("файл"))
    }

    @Test("Стадии идут в порядке сборки: план → индекс → память → граф → скиллы → влияние → файлы")
    func stagesAreOrdered() {
        #expect(ContextStageLogLogic.Stage.allCases == [
            .planning, .index, .memory, .graph, .skills, .impact, .files
        ])
    }

    @Test("Счётчики попадают в строку, когда известны")
    func countsAreShown() {
        let line = ContextStageLogLogic.line(for: .files, detail: "3 из 8")
        #expect(line.contains("3 из 8"))
        #expect(!line.contains("\n"))
    }

    @Test("Пустая деталь не оставляет висящих разделителей")
    func emptyDetailIsClean() {
        let line = ContextStageLogLogic.line(for: .graph, detail: "")
        #expect(!line.hasSuffix("·"))
        #expect(!line.contains("  "))
    }

    @Test("Финальная строка честно говорит, что контекст собран")
    func doneLineIsHonest() {
        let line = ContextStageLogLogic.doneLine(fileCount: 4, memoryCount: 2, hasGraph: true)
        #expect(line.contains("4"))
        #expect(line.contains("2"))
        #expect(line.contains("граф"))
    }

    @Test("Финальная строка без источников не врёт о собранном контексте")
    func doneLineWithoutSources() {
        let line = ContextStageLogLogic.doneLine(fileCount: 0, memoryCount: 0, hasGraph: false)
        #expect(line.lowercased().contains("без источников") || line.contains("0"))
    }
}
