import Foundation
import Testing
@testable import myCoder

/// Чтение текста файла с fallback по кодировкам: UTF-8 → UTF-16 → Latin-1.
/// Сборка точечного промпта не должна дропать файл только потому, что он
/// сохранён не в UTF-8 (запрос 2026-11-13).
@MainActor
@Suite("Декодирование текста файла")
struct ContextFileDecodingTests {

    private func makeFile(_ name: String, data: Data) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-decoding-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    @Test("UTF-8 читается как есть")
    func utf8() throws {
        let url = try makeFile("a.txt", data: Data("привет utf8\n".utf8))
        #expect(ContextFileDecoding.readText(url: url) == "привет utf8\n")
    }

    @Test("UTF-16 (little endian) читается через fallback")
    func utf16() throws {
        var data = Data([0xFF, 0xFE]) // BOM
        let text = "привет utf16"
        for unit in text.utf16 { data.append(UInt8(unit & 0xFF)); data.append(UInt8(unit >> 8)) }
        let url = try makeFile("b.txt", data: data)
        #expect(ContextFileDecoding.readText(url: url) == text)
    }

    @Test("Latin-1 читается через fallback")
    func latin1() throws {
        var bytes: [UInt8] = []
        for byte in "caf\u{00E9}".utf8 { bytes.append(byte) }
        // «café» в Latin-1: 0x63 0x61 0x66 0xE9
        let latinBytes: [UInt8] = [0x63, 0x61, 0x66, 0xE9]
        let url = try makeFile("c.txt", data: Data(latinBytes))
        #expect(ContextFileDecoding.readText(url: url) == "caf\u{00E9}")
    }

    @Test("Бинарный файл (NUL-насыщенный) не принимается как текст")
    func binaryData() throws {
        // utf8 декодирует NUL валидно, utf16 — тоже; эвристика «похоже на
        // текст» должна отсечь оба пути как нетекстовые.
        let url = try makeFile("d.bin", data: Data([0x00, 0x00, 0x00, 0x00, 0x61, 0x00]))
        #expect(ContextFileDecoding.readText(url: url) == nil)
    }
}
