import Foundation

/// Serializes the message `metadata` column.
///
/// New rows carry a small envelope with the send info and the honest reason
/// for a missing context pack. Old rows contain a bare `MessageSendInfo` JSON;
/// they keep decoding exactly as before. Without this, `contextSummary` lived
/// only in memory and disappeared on reload — a message with no compiled pack
/// then showed no context button at all.
enum MessageMetadataCodec {

    struct Decoded: Equatable {
        let sendInfo: MessageSendInfo?
        let contextSummary: String?
    }

    private struct Envelope: Codable {
        var sendInfo: MessageSendInfo?
        var contextSummary: String?
    }

    static func encode(sendInfo: MessageSendInfo?, contextSummary: String?) -> String? {
        let summary = contextSummary?.trimmingCharacters(in: .whitespacesAndNewlines)
        let envelope = Envelope(
            sendInfo: sendInfo,
            contextSummary: (summary?.isEmpty ?? true) ? nil : summary
        )
        guard envelope.sendInfo != nil || envelope.contextSummary != nil else { return nil }
        guard let data = try? JSONEncoder().encode(envelope) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func encodeLegacySendInfoOnly(_ info: MessageSendInfo) -> String? {
        guard let data = try? JSONEncoder().encode(info) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ json: String?) -> Decoded {
        guard let json, !json.isEmpty, let data = json.data(using: .utf8) else {
            return Decoded(sendInfo: nil, contextSummary: nil)
        }
        // New envelope first. The check on `Envelope` is unambiguous: a bare
        // MessageSendInfo has no `sendInfo` key.
        if let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
           envelope.sendInfo != nil || envelope.contextSummary != nil {
            return Decoded(sendInfo: envelope.sendInfo, contextSummary: envelope.contextSummary)
        }
        // Legacy row: the whole JSON is MessageSendInfo.
        let info = try? JSONDecoder().decode(MessageSendInfo.self, from: data)
        return Decoded(sendInfo: info, contextSummary: nil)
    }
}
