import Foundation

// ═══════════════════════════════════════════════════════════════════════════
// Round 9 — Web model discovery from the actual page (TDD implementation).
//
// Discovery uses the vendor-specific selectors from
// `web_providers_catalog.json`, not hardcoded strings. Failure to discover
// is surfaced explicitly instead of silently falling back to vendor
// defaults, so stale hardcoded lists are never presented as live.
// ═══════════════════════════════════════════════════════════════════════════

/// Catalog JSON structure for one vendor entry.
    private struct WebVendorCatalogEntryDTO: Decodable {
        let id: String
        let models: [String]?
        let chatURL: String?
        let loginURL: String?
        let selectors: Selectors
        struct Selectors: Decodable {
            let input: String?
            let sendButton: String?
            let responseContainer: String?
            let stopButton: String?
            let modelDropdown: String?
            let effortDropdown: String?
            let modelButton: String?
            let modelItem: String?
            let newChatTexts: [String]?
            let newChatSelector: String?
            let modeSelect: String?
            let thinkingSelect: String?
            let effortItem: String?
            let modeItem: String?
        }
    }

/// Catalog-backed selectors/URLs for each web-chat vendor.
/// Source of truth: `myCoder/Sources/Resources/Catalog/web_providers_catalog.json`
struct WebProviderCatalog {
    struct VendorEntry: Equatable {
        let id: String
        let models: [String]
        let input: String?
        let sendButton: String?
        let responseContainer: String?
        let stopButton: String?
        let modelDropdown: String
        let effortDropdown: String?
        let modelButton: String?
        let modelItem: String?
        let newChatTexts: [String]?
        let newChatSelector: String?
        let modeSelect: String?
        let thinkingSelect: String?
        let effortItem: String?
        let modeItem: String?
    }

    private struct RootDTO: Decodable { let vendors: [WebVendorCatalogEntryDTO] }

    private let entries: [String: VendorEntry]

    private init(entries: [String: VendorEntry], loginURLs: [String: String] = [:]) {
        self.entries = entries
        self.loginURLs = loginURLs
    }

    /// Decodes the catalog, building both the selector map and login URLs.
    private static func decode(_ data: Data) throws -> WebProviderCatalog {
        let root = try JSONDecoder().decode(RootDTO.self, from: data)
        let map: [String: VendorEntry] = Dictionary(uniqueKeysWithValues:
            root.vendors.compactMap { dto in
                guard let selector = dto.selectors.modelDropdown, !selector.isEmpty else { return nil }
                return (dto.id, VendorEntry(id: dto.id, models: dto.models ?? [], input: dto.selectors.input, sendButton: dto.selectors.sendButton, responseContainer: dto.selectors.responseContainer, stopButton: dto.selectors.stopButton, modelDropdown: selector, effortDropdown: dto.selectors.effortDropdown, modelButton: dto.selectors.modelButton, modelItem: dto.selectors.modelItem, newChatTexts: dto.selectors.newChatTexts, newChatSelector: dto.selectors.newChatSelector, modeSelect: dto.selectors.modeSelect, thinkingSelect: dto.selectors.thinkingSelect, effortItem: dto.selectors.effortItem, modeItem: dto.selectors.modeItem))
            })
        let logins: [String: String] = Dictionary(uniqueKeysWithValues:
            root.vendors.compactMap { dto in
                guard let login = dto.loginURL, !login.isEmpty else { return nil }
                return (dto.id, login)
            })
        return WebProviderCatalog(entries: map, loginURLs: logins)
    }

    static func loadBundled() throws -> WebProviderCatalog {
        let bundleURLs = [
            Bundle.module.url(forResource: "web_providers_catalog", withExtension: "json"),
            Bundle.main.url(forResource: "web_providers_catalog", withExtension: "json"),
        ]
        for u in bundleURLs.compactMap({ $0 }) {
            guard let data = try? Data(contentsOf: u) else { continue }
            return try decode(data)
        }
        // Fallback for tests (SPM resources live in the repo source tree).
        let candidates = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent(),
        ]
        for base in candidates {
            let url = base.appendingPathComponent("myCoder/Sources/Resources/Catalog/web_providers_catalog.json")
            guard let data = try? Data(contentsOf: url) else { continue }
            return try decode(data)
        }
        throw NSError(domain: "WebProviderCatalog", code: 1, userInfo: [NSLocalizedDescriptionKey: "web_providers_catalog.json not found in bundle or repo"])
    }

    func selectors(for vendorID: String) -> VendorEntry? {
        entries[vendorID]
    }

    /// Catalog model lists (from live site inspection). Empty when a vendor
    /// provides no stable list (e.g. ChatGPT — models change frequently).
    func models(for vendorID: String) -> [String] {
        entries[vendorID]?.models ?? []
    }

    /// Login page URL for a vendor from the catalog; nil falls back to the
    /// vendor's chat URL in the caller.
    func loginURL(for vendorID: String) -> String? {
        loginURLs[vendorID]
    }

    private let loginURLs: [String: String]
}
