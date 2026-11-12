import Foundation

/// Надёжное чтение текста файла для сборки контекста: пробуем UTF-8,
/// затем UTF-16 (BOM/LE), затем Latin-1. Даже если файл сохранён не в
/// UTF-8, сборка точечного промпта не должна дропать его (запрос
/// 2026-11-13). Двоичные данные отсекаются эвристикой «похоже на текст».
enum ContextFileDecoding {

    /// Читает файл как текст, либо возвращает nil, если ни одна текстовая
    /// кодировка не дала правдоподобного текста.
    static func readText(url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        // UTF-16 выбираем первым только при явном BOM или при байтах с
        // нулями (типично для UTF-16 без BOM). Иначе Latin-1 «декодирует»
        // что угодно и перехватит utf16-файлы раньше, чем они попробуют.
        let hasUTF16BOM = data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF])
        let likelyUTF16 = hasUTF16BOM || (data.count % 2 == 0 && data.contains(0))
        if likelyUTF16, let text = String(data: data, encoding: .utf16), looksLikeText(text) {
            return text
        }
        if let text = String(data: data, encoding: .utf8), looksLikeText(text) {
            return text
        }
        if let text = String(data: data, encoding: .isoLatin1), looksLikeText(text) {
            return text
        }
        return nil
    }

    /// Эвристика: текст не должен состоять по большей части из управляющих
    /// символов (кроме табуляции/переноса). Отсекает двоичные файлы,
    /// которые «декодируются» в любую кодировку без ошибки.
    static func looksLikeText(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        var control = 0
        for scalar in text.unicodeScalars {
            if scalar.value < 0x20, scalar.value != 0x09, scalar.value != 0x0A, scalar.value != 0x0D {
                control += 1
            }
        }
        return Double(control) / Double(text.count) <= 0.05
    }
}
