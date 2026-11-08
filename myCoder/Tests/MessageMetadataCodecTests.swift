import Testing
import Foundation
@testable import myCoder

/// `contextSummary` used to live only in memory: after a session reload the
/// honest reason for a missing pack was gone, so a message with no compiled
/// part showed no context button at all. The metadata column now carries both
/// the send info and the summary, while old rows with a bare `MessageSendInfo`
/// JSON keep loading unchanged.
@Suite("Метаданные сообщения: sendInfo + contextSummary")
struct MessageMetadataCodecTests {

    private func sendInfo() -> MessageSendInfo {
        MessageSendInfo(
            modelID: "beam",
            providerID: "local",
            temperature: 0.4,
            topP: 0.9,
            maxTokens: 2048,
            systemPrompt: "rules",
            variant: "high",
            tools: ["read_file"],
            sentAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    @Test("sendInfo и причина отсутствия пакета переживают кодирование")
    func roundTripsBothValues() throws {
        let info = sendInfo()
        let json = try #require(MessageMetadataCodec.encode(
            sendInfo: info,
            contextSummary: "Чат без проекта — контекста нет."
        ))
        let decoded = MessageMetadataCodec.decode(json)
        #expect(decoded.sendInfo == info)
        #expect(decoded.contextSummary == "Чат без проекта — контекста нет.")
    }

    @Test("Пустая причина не пишется в метаданные")
    func emptySummaryIsNil() {
        let json = MessageMetadataCodec.encode(sendInfo: sendInfo(), contextSummary: "   ")
        let decoded = MessageMetadataCodec.decode(json)
        #expect(decoded.contextSummary == nil)
        #expect(decoded.sendInfo == sendInfo())
    }

    @Test("Старая строка с чистым MessageSendInfo читается как раньше")
    func legacySendInfoJSONStillDecodes() throws {
        let info = sendInfo()
        let legacyJSON = try #require(MessageMetadataCodec.encodeLegacySendInfoOnly(info))
        let decoded = MessageMetadataCodec.decode(legacyJSON)
        #expect(decoded.sendInfo == info)
        #expect(decoded.contextSummary == nil)
    }

    @Test("Пустые метаданные дают nil без падения")
    func nilMetadataDecodesCleanly() {
        let decoded = MessageMetadataCodec.decode(nil)
        #expect(decoded.sendInfo == nil)
        #expect(decoded.contextSummary == nil)
    }
}
