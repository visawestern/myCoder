import Testing
import Foundation
@testable import myCoder

@Suite("Message Parts Serve Contract")
struct MessagePartsServeContractTests {

    @Test("Decoded file image part restores attached image")
    func decodeFileImagePart() throws {
        let json = """
        {"info":{"id":"msg_img","role":"user"},"parts":[{"type":"file","mime":"image/png","url":"data:image/png;base64,aGVsbG8="}]}
        """
        let message = try JSONDecoder().decode(MimoMessageResponse.self, from: Data(json.utf8))
        let mapped = MessageStore.message(from: message)
        #expect(mapped.attachedImages?.count == 1)
        #expect(mapped.attachedImages?.first?.base64 == "aGVsbG8=")
    }
}
