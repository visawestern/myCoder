import Testing
@testable import myCoder

struct ProviderNameLogicTests {
    @Test func blankNameFallsBackToTypeName() {
        #expect(ProviderNameLogic.resolvedName("", fallback: "OpenAI", existing: []) == "OpenAI")
        #expect(ProviderNameLogic.resolvedName("   ", fallback: "NVIDIA", existing: []) == "NVIDIA")
    }

    @Test func keepsUniqueName() {
        #expect(ProviderNameLogic.resolvedName("My NVIDIA", fallback: "NVIDIA", existing: ["OpenAI"]) == "My NVIDIA")
    }

    @Test func appendsNumberOnDuplicate() {
        #expect(ProviderNameLogic.resolvedName("NVIDIA", fallback: "NVIDIA", existing: ["NVIDIA"]) == "NVIDIA 2")
        #expect(ProviderNameLogic.resolvedName("NVIDIA", fallback: "NVIDIA", existing: ["NVIDIA", "NVIDIA 2"]) == "NVIDIA 3")
    }

    @Test func duplicateMatchIsCaseInsensitive() {
        #expect(ProviderNameLogic.resolvedName("nvidia", fallback: "NVIDIA", existing: ["NVIDIA"]) == "nvidia 2")
    }
}
