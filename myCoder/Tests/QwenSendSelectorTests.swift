import Testing
import Foundation
@testable import myCoder

/// Round 30 — live user-pipeline finding: Qwen's `.message-input-right-button-send`
/// is a DIV wrapper whose programmatic click() is a no-op; only the INNER
/// `<button class="send-button">` actually submits. The sendButton selector must
/// therefore target the inner button BEFORE any wrapper.
@Suite("Round 30 — Qwen sendButton selector targets the real button first")
struct QwenSendSelectorTests {

    private func qwenSendButton() throws -> String {
        let entry = try WebProviderCatalog.loadBundled().selectors(for: "qwen")
        return entry?.sendButton ?? ""
    }

    @Test("first selector candidate is an inner <button>, not the div wrapper")
    func innerButtonComesFirst() throws {
        let selector = try qwenSendButton()
        #expect(!selector.isEmpty, "catalog must define a qwen sendButton")
        let first = selector.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        #expect(first.contains("button"),
                "first candidate must match a <button> element (wrapper div clicks are no-ops), got: '\(first)'")
    }

    @Test("wrapper fallback is still present for older page versions")
    func wrapperFallbackRetained() throws {
        let selector = try qwenSendButton()
        #expect(selector.contains(".message-input-right-button-send"),
                "old wrapper must remain as a later fallback")
    }

    // MARK: - Round 30b: live DOM adaptation (2026-08-23)

    private func qwenEntry() throws -> (effortDropdown: String, effortItem: String) {
        let entry = try WebProviderCatalog.loadBundled().selectors(for: "qwen")
        return (entry?.effortDropdown ?? "", entry?.effortItem ?? "")
    }

    @Test("effort trigger targets the inner dropdown-menu trigger first")
    func effortTriggerTargetsInnerTrigger() throws {
        let e = try qwenEntry()
        let first = e.effortDropdown.split(separator: ",").first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        #expect(first.contains("dropdown-menu-trigger"),
                "wrapper .qwen-thinking-selector click() does not open the menu; got '\(first)'")
    }

    @Test("effort item selector covers the v2 menu items")
    func effortItemCoversMenuItems() throws {
        let e = try qwenEntry()
        #expect(e.effortItem.contains("qwen-chat-v2-dropdown-menu-item"),
                "live options render as .qwen-chat-v2-dropdown-menu-item[role=menuitem]; got '\(e.effortItem)'")
    }
}
