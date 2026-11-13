import Testing
import Foundation
@testable import myCoder

/// The navigator numbers the WHOLE session, not just the page that happens to
/// be loaded. The index is built once per chat from lightweight DB rows and is
/// kept in memory, so the list can show every user message even when its page
/// is not in the feed.
@Suite("User message index — whole session, not the loaded page")
struct UserMessageIndexLogicTests {

    private func record(
        _ id: String,
        _ text: String,
        truncated: Bool = false
    ) -> UserMessageIndexRecord {
        UserMessageIndexRecord(id: id, contentPrefix: text, isTruncated: truncated)
    }

    private func message(
        _ id: String,
        role: MessageRole = .user,
        content: String = ""
    ) -> Message {
        Message(id: id, role: role, content: content)
    }

    @Test("Records become sequentially numbered entries")
    func entriesAreNumbered() {
        let entries = UserMessageIndexLogic.entries(from: [
            record("u1", "first"),
            record("u2", "second"),
            record("u3", "third"),
        ])
        #expect(entries.map(\.id) == ["u1", "u2", "u3"])
        #expect(entries.map(\.ordinal) == [1, 2, 3])
        #expect(entries.map(\.preview) == ["first", "second", "third"])
    }

    @Test("Blank previews are not numbered")
    func blankRecordsAreSkipped() {
        let entries = UserMessageIndexLogic.entries(from: [
            record("u1", "first"),
            record("blank", "   \n  "),
            record("u3", "third"),
        ])
        #expect(entries.map(\.id) == ["u1", "u3"])
        #expect(entries.map(\.ordinal) == [1, 2])
    }

    @Test("A truncated stored prefix keeps the ellipsis")
    func truncatedPreviewKeepsEllipsis() {
        let entries = UserMessageIndexLogic.entries(from: [
            record("u1", String(repeating: "a", count: 300), truncated: true),
        ])
        #expect(entries.count == 1)
        #expect(entries[0].preview.hasSuffix("…"))
        #expect(entries[0].preview.count <= 101)
    }

    @Test("Loaded messages refresh previews without reordering")
    func mergingRefreshesPreviews() {
        let base = UserMessageIndexLogic.entries(from: [
            record("u1", "old preview"),
            record("u2", "second"),
        ])
        let merged = UserMessageIndexLogic.merging(
            messages: [message("u1", content: "fresh preview")],
            into: base
        )
        #expect(merged.map(\.id) == ["u1", "u2"])
        #expect(merged[0].preview == "fresh preview")
        #expect(merged.map(\.ordinal) == [1, 2])
    }

    @Test("Live tail messages are appended after the stored index")
    func mergingAppendsLiveTail() {
        let base = UserMessageIndexLogic.entries(from: [
            record("u1", "first"),
            record("u2", "second"),
        ])
        let merged = UserMessageIndexLogic.merging(
            messages: [
                message("u1", content: "first"),
                message("a1", role: .assistant, content: "answer"),
                message("u2", content: "second"),
                message("u3", content: "live third"),
            ],
            into: base
        )
        #expect(merged.map(\.id) == ["u1", "u2", "u3"])
        #expect(merged.map(\.ordinal) == [1, 2, 3])
        #expect(merged.last?.preview == "live third")
    }

    @Test("A server-only older page is inserted before the known neighbour")
    func mergingInsertsOlderPage() {
        let base = UserMessageIndexLogic.entries(from: [
            record("u3", "third"),
            record("u4", "fourth"),
        ])
        let merged = UserMessageIndexLogic.merging(
            messages: [
                message("u1", content: "first"),
                message("u2", content: "second"),
                message("u3", content: "third"),
            ],
            into: base
        )
        #expect(merged.map(\.id) == ["u1", "u2", "u3", "u4"])
        #expect(merged.map(\.ordinal) == [1, 2, 3, 4])
    }

    @Test("A server-only message between two known rows lands in its gap")
    func mergingInsertsMiddlePage() {
        let base = UserMessageIndexLogic.entries(from: [
            record("u1", "first"),
            record("u4", "fourth"),
        ])
        let merged = UserMessageIndexLogic.merging(
            messages: [
                message("u2", content: "second"),
                message("u3", content: "third"),
                message("u4", content: "fourth"),
            ],
            into: base
        )
        #expect(merged.map(\.id) == ["u1", "u2", "u3", "u4"])
    }

    @Test("Appending is idempotent and ignores assistant rows")
    func appendIsIdempotent() {
        var entries = UserMessageIndexLogic.entries(from: [record("u1", "first")])
        entries = UserMessageIndexLogic.appending(message("u2", content: "second"), to: entries)
        entries = UserMessageIndexLogic.appending(message("u2", content: "second"), to: entries)
        entries = UserMessageIndexLogic.appending(
            message("a1", role: .assistant, content: "answer"),
            to: entries
        )
        #expect(entries.map(\.id) == ["u1", "u2"])
        #expect(entries.map(\.ordinal) == [1, 2])
    }

    @Test("Removing renumbers the remaining entries")
    func removingRenumbers() {
        let entries = UserMessageIndexLogic.entries(from: [
            record("u1", "first"),
            record("u2", "second"),
            record("u3", "third"),
        ])
        let reduced = UserMessageIndexLogic.removing(id: "u2", from: entries)
        #expect(reduced.map(\.id) == ["u1", "u3"])
        #expect(reduced.map(\.ordinal) == [1, 2])
    }

    @Test("A fresh in-memory chat can build the index from loaded messages")
    func entriesFromMessages() {
        let entries = UserMessageIndexLogic.entries(fromMessages: [
            message("u1", content: "first"),
            message("a1", role: .assistant, content: "answer"),
            message("u2", content: "second"),
        ])
        #expect(entries.map(\.id) == ["u1", "u2"])
        #expect(entries.map(\.ordinal) == [1, 2])
    }
}
