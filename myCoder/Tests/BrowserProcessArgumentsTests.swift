import Foundation
import Testing
@testable import myCoder

@Suite("Engine launch arguments")
@MainActor
struct BrowserProcessArgumentsTests {
    @Test func onlyPersistentProfileIsPassed() {
        let app = URL(fileURLWithPath: "/not-launched/Chromium.app")
        let engine = AntiBrowserEngineInfo(appURL: app,
                                          binaryURL: app.appendingPathComponent("Contents/MacOS/Chromium"),
                                          version: "156")
        let profile = URL(fileURLWithPath: "/tmp/profile with spaces")
        let config = BrowserProcess.Config(profileDir: profile, engine: engine)
        #expect(config.launchArguments == ["--user-data-dir=/tmp/profile with spaces"])
    }

    @Test func legacyHeadlessSettingCannotAddAnArgument() throws {
        let source = try RepoRoot.sourceText("myCoder/Sources/Services/EngineStatusCenter.swift")
        #expect(!source.contains("config.headless"))
        let launcher = try RepoRoot.sourceText("myCoder/Sources/Services/BrowserProcess.swift")
        #expect(!launcher.contains("args.append(\"--headless\")"))
        #expect(launcher.contains("process.arguments = config.launchArguments"))
    }
}
