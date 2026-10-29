import Foundation

/// Chooses the part flow a message row renders.
///
/// Direct/Auto Free turns used to persist reasoning and tool parts while
/// keeping the answer only in `content`. The row rendered that content above
/// every part, so a finished reply showed its answer first and the reasoning
/// spoiler at the very end. New turns store the answer as a real text part;
/// this fallback keeps already-persisted messages in the same order by
/// appending the missing text at the end of their block flow.
enum MessageRowPartsLogic {
    static func displayParts(
        parts: [MessagePartContent],
        content: String
    ) -> [MessagePartContent] {
        for part in parts {
            if case .text(let text) = part,
               MessageContentSanitizerLogic.sanitizedTextPart(text) != nil {
                return parts
            }
        }
        guard !content.isEmpty,
              MessageContentSanitizerLogic.sanitizedTextPart(content) != nil else {
            return parts
        }
        return parts + [.text(content)]
    }
}
