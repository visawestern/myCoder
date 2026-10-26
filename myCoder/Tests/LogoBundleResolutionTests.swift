import Testing
import Foundation
@testable import myCoder

@Suite("Logo resource bundle resolution (rename/mycoder R7b)")
struct LogoBundleResolutionTests {

    @Test func candidateBundlesUseMycoderName() {
        let bundles = MiMoLogoLoader.candidateBundleNames()
        #expect(!bundles.isEmpty)
        #expect(bundles.allSatisfy { $0 == "myCoder_myCoder.bundle" })
        #expect(!bundles.joined().contains("MyCoder"))
    }

    @Test func resourceNameIsMycoderMark() {
        #expect(MiMoLogoLoader.resourceName == "myCoderMark")
    }
}
