import Foundation

/// One piece of the assembled context that fits the remote model window.
struct PromptChunk: Equatable {
    /// 1-based position of the piece.
    let index: Int
    /// How many pieces the context was split into.
    let total: Int
    /// The text of the piece (the continuation marker is already included).
    let text: String
}

/// Splits the assembled context into pieces that fit the remote model window.
///
/// The only volume limit is the window of the remote model (user directive
/// D5): everything above it is sent as several chunks, each marked as
/// "часть i/n", so the model knows it must wait for all of them.
enum PromptChunker {

    /// Bytes reserved for the continuation marker of a chunk.
    private static let markerReserve = 160

    static func chunk(context: String,
                      limitBytes: Int,
                      model: String = "remote model") throws -> [PromptChunk] {
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard limitBytes > markerReserve else {
            throw LocalCompilerError.promptDoesNotFit(model: model, bytes: trimmed.utf8.count, limit: limitBytes)
        }

        let budget = limitBytes - markerReserve
        let pieces = try splitPieces(context: trimmed, budget: budget, model: model)

        var chunks: [String] = []
        var current: [String] = []
        var currentSize = 0
        for piece in pieces {
            let pieceSize = piece.utf8.count + 1
            if !current.isEmpty, currentSize + pieceSize > budget {
                chunks.append(current.joined(separator: "\n"))
                current = []
                currentSize = 0
            }
            current.append(piece)
            currentSize += pieceSize
        }
        if !current.isEmpty {
            chunks.append(current.joined(separator: "\n"))
        }

        let total = chunks.count
        return chunks.enumerated().map { offset, text in
            let index = offset + 1
            let body = index == 1 ? text : marker(index: index, total: total) + text
            return PromptChunk(index: index, total: total, text: body)
        }
    }

    /// The continuation marker: the model must wait for all chunks (D6).
    static func marker(index: Int, total: Int) -> String {
        "[часть \(index)/\(total) — продолжение контекста; дождись всех частей]\n"
    }

    // MARK: - Splitting

    /// Splits the context into header blocks ("## …", "### …") and, when a
    /// block is too big, into line groups. A single line that does not fit is
    /// an error — content is never silently cut.
    private static func splitPieces(context: String, budget: Int, model: String) throws -> [String] {
        var pieces: [String] = []
        var current: [String] = []

        func flush() {
            if !current.isEmpty {
                pieces.append(current.joined(separator: "\n"))
                current = []
            }
        }

        for line in context.components(separatedBy: "\n") {
            if isHeader(line), !current.isEmpty {
                flush()
            }
            if line.utf8.count > budget {
                flush()
                throw LocalCompilerError.promptDoesNotFit(
                    model: model,
                    bytes: line.utf8.count,
                    limit: budget
                )
            }
            let projected = current.reduce(0) { $0 + $1.utf8.count + 1 }
            if !current.isEmpty, projected + line.utf8.count + 1 > budget {
                flush()
            }
            current.append(line)
        }
        flush()
        return pieces
    }

    private static func isHeader(_ line: String) -> Bool {
        line.hasPrefix("## ") || line.hasPrefix("### ")
    }
}
