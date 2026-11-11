import Testing
import AppKit
import Foundation
@testable import myCoder

/// Логика приёма файлов из pasteboard/drag: извлечение URL, дедупликация,
/// приёмлемость, legacy NSFilenames, приоритет файлов над изображениями.
@MainActor
@Suite("FileDropLogic")
struct FileDropLogicTests {

    private func makePasteboard(_ name: String) -> NSPasteboard {
        let board = NSPasteboard(name: NSPasteboard.Name(name))
        board.clearContents()
        return board
    }

    @Test("fileURLs извлекает URL-объекты и дедуплицирует")
    func fileURLsExtractAndDeduplicate() throws {
        let board = makePasteboard("filedrop-test-\(UUID().uuidString)")
        let url = URL(fileURLWithPath: "/tmp/a.txt")
        board.writeObjects([url as NSURL, url as NSURL])
        let urls = FileDropLogic.fileURLs(from: board)
        let paths = Set(urls.map(\.path))
        #expect(paths == ["/tmp/a.txt"])
    }

    @Test("fileURLs поддерживает legacy NSFilenames и строковый fileURL")
    func fileURLsLegacyAndString() throws {
        let board = makePasteboard("filedrop-legacy-\(UUID().uuidString)")
        board.setPropertyList(["/tmp/b.txt", "/tmp/c.txt"], forType: FileDropLogic.legacyFilenamesType)
        let urls = FileDropLogic.fileURLs(from: board)
        let paths = Set(urls.map(\.path))
        #expect(paths.contains("/tmp/b.txt"))
        #expect(paths.contains("/tmp/c.txt"))

        let board2 = makePasteboard("filedrop-string-\(UUID().uuidString)")
        board2.setString("file:///tmp/d.txt", forType: .fileURL)
        #expect(FileDropLogic.fileURLs(from: board2).map(\.path) == ["/tmp/d.txt"])
    }

    @Test("fileURLs игнорирует не-file URL")
    func fileURLsIgnoresNonFile() throws {
        let board = makePasteboard("filedrop-http-\(UUID().uuidString)")
        board.writeObjects([URL(string: "https://example.com/x")! as NSURL])
        #expect(FileDropLogic.fileURLs(from: board).isEmpty)
    }

    @Test("canAccept: false на пустом pasteboard")
    func canAcceptEmpty() {
        let board = makePasteboard("filedrop-empty-\(UUID().uuidString)")
        #expect(!FileDropLogic.canAccept(pasteboard: board))
    }

    @Test("canAccept: true при наличии файлов")
    func canAcceptWithFiles() throws {
        let board = makePasteboard("filedrop-accept-\(UUID().uuidString)")
        board.setPropertyList(["/tmp/e.txt"], forType: FileDropLogic.legacyFilenamesType)
        #expect(FileDropLogic.canAccept(pasteboard: board))
    }

    @Test("MimoServeError описания")
    func mimoServeErrorDescriptions() {
        #expect(MimoServeError.httpError(statusCode: 500, message: "boom").errorDescription == "HTTP error 500: boom")
        #expect(MimoServeError.httpError(statusCode: 500, message: nil).errorDescription == "HTTP error 500")
        #expect(MimoServeError.connectionFailed.errorDescription == "Connection failed")
        #expect(MimoServeError.emptyResponse.errorDescription == ProviderResponseValidationLogic.emptyCompletionMessage)
        #expect(MimoServeError.sessionBusy.errorDescription?.contains("busy") == true)
    }
}
