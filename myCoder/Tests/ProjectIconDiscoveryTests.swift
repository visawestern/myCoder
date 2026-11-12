import Testing
import Foundation
@testable import myCoder

/// Project icon discovery must look only at the project's own root folder:
/// a favicon/logo that lives in a submodule or node_modules is NOT the
/// project's icon and must be ignored (user directive 2026-11-12).
@Suite("Project icon discovery")
struct ProjectIconDiscoveryTests {

    private func makeRoot(_ name: String = "IconRoot") throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("project-icon-tests-\(UUID().uuidString)")
            .appendingPathComponent(name)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func touch(_ url: URL) throws {
        try Data("x".utf8).write(to: url)
    }

    @Test("Returns favicon.ico in the project root")
    func findsFaviconIco() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let icon = root.appendingPathComponent("favicon.ico")
        try touch(icon)

        let found = ProjectIconDiscovery.iconURL(forProjectAt: root.path)
        #expect(found == icon)
    }

    @Test("Recognition is case-insensitive")
    func matchesCaseInsensitively() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let icon = root.appendingPathComponent("Favicon.PNG")
        try touch(icon)

        let found = ProjectIconDiscovery.iconURL(forProjectAt: root.path)
        #expect(found == icon)
    }

    @Test("Favicon is preferred over a generic logo when both exist in the root")
    func prioritizesFaviconOverLogo() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let favicon = root.appendingPathComponent("favicon.png")
        let logo = root.appendingPathComponent("logo.png")
        try touch(favicon)
        try touch(logo)

        let found = ProjectIconDiscovery.iconURL(forProjectAt: root.path)
        #expect(found == favicon)
    }

    @Test("PNG logo is preferred over SVG logo")
    func prioritizesPngOverSvg() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let png = root.appendingPathComponent("logo.png")
        let svg = root.appendingPathComponent("logo.svg")
        try touch(png)
        try touch(svg)

        let found = ProjectIconDiscovery.iconURL(forProjectAt: root.path)
        #expect(found == png)
    }

    @Test("A directory named like an icon is skipped")
    func skipsDirectories() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("favicon.png"),
            withIntermediateDirectories: true
        )

        let found = ProjectIconDiscovery.iconURL(forProjectAt: root.path)
        #expect(found == nil)
    }

    @Test("Icon inside node_modules is ignored when the root has none")
    func ignoresNodeModulesIcons() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let nodeModules = root.appendingPathComponent("node_modules/dep/assets")
        try FileManager.default.createDirectory(at: nodeModules, withIntermediateDirectories: true)
        try touch(nodeModules.appendingPathComponent("favicon.ico"))

        let found = ProjectIconDiscovery.iconURL(forProjectAt: root.path)
        #expect(found == nil)
    }

    @Test("Icon inside a git submodule is ignored when the root has none")
    func ignoresSubmoduleIcons() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let submodule = root.appendingPathComponent("vendor/submodule")
        try FileManager.default.createDirectory(at: submodule, withIntermediateDirectories: true)
        try touch(submodule.appendingPathComponent("logo.png"))

        let found = ProjectIconDiscovery.iconURL(forProjectAt: root.path)
        #expect(found == nil)
    }

    @Test("Empty or missing root yields nil")
    func emptyAndMissingRootsYieldNil() throws {
        let empty = try makeRoot("Empty")
        defer { try? FileManager.default.removeItem(at: empty) }
        #expect(ProjectIconDiscovery.iconURL(forProjectAt: empty.path) == nil)

        let missing = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("definitely-missing-project-icon-root")
        #expect(ProjectIconDiscovery.iconURL(forProjectAt: missing.path) == nil)
    }

    @Test("Finds icon in a standard project subfolder when the root has none")
    func findsIconInAssetsWhenRootHasNone() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let assets = root.appendingPathComponent("assets")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let icon = assets.appendingPathComponent("logo.png")
        try touch(icon)

        let found = ProjectIconDiscovery.iconURL(forProjectAt: root.path)
        #expect(found == icon)
    }

    @Test("Root icon wins over a subfolder icon")
    func rootWinsOverSubfolder() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let rootIcon = root.appendingPathComponent("favicon.png")
        let assets = root.appendingPathComponent("public")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let assetsIcon = assets.appendingPathComponent("logo.png")
        try touch(rootIcon)
        try touch(assetsIcon)

        let found = ProjectIconDiscovery.iconURL(forProjectAt: root.path)
        #expect(found == rootIcon)
    }

    @Test("node_modules is never scanned, even with a subfolder icon")
    func ignoresNodeModulesEvenWithSubfolderIcons() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let nodeModules = root.appendingPathComponent("node_modules/assets")
        try FileManager.default.createDirectory(at: nodeModules, withIntermediateDirectories: true)
        try touch(nodeModules.appendingPathComponent("logo.png"))

        let found = ProjectIconDiscovery.iconURL(forProjectAt: root.path)
        #expect(found == nil)
    }

    @Test("Nesting deeper than one level is not searched")
    func ignoresDeeperNesting() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("assets/icons")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try touch(nested.appendingPathComponent("logo.png"))

        let found = ProjectIconDiscovery.iconURL(forProjectAt: root.path)
        #expect(found == nil)
    }

    @Test("Non-standard subfolders are not searched")
    func ignoresNonStandardSubfolders() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let custom = root.appendingPathComponent("my-assets")
        try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
        try touch(custom.appendingPathComponent("logo.png"))

        let found = ProjectIconDiscovery.iconURL(forProjectAt: root.path)
        #expect(found == nil)
    }

    @Test("Mac app icon bundle match", .timeLimit(.minutes(1)))
    func findsIcnsInResources() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = root.appendingPathComponent("Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let icon = resources.appendingPathComponent("AppIcon.icns")
        try touch(icon)

        let found = ProjectIconDiscovery.iconURL(forProjectAt: root.path)
        #expect(found == icon)
    }
}
