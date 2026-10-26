import Foundation

struct MessageSendOptions: Equatable {
    let agent: String
    let modelID: String?
    let providerID: String?
    let variant: String?
    let messageID: String?
    let permission: [String: String]?

    init(agent: String, modelID: String? = nil, providerID: String? = nil, variant: String? = nil, messageID: String? = nil, permission: [String: String]? = nil) {
        self.agent = agent
        self.modelID = modelID
        self.providerID = providerID
        self.variant = variant
        self.messageID = messageID
        self.permission = permission
    }

    /// Builds the serve request body. E06 (Раздел 9 п.49): call parameters
    /// temperature/max_tokens/top_p chosen in the model menu used to be dropped
    /// on the serve path — they are now merged in when customized.
    func requestBody(parts: [[String: Any]], parameters: ModelCallParameters = ModelCallParameters()) -> [String: Any] {
        var body: [String: Any] = [
            "parts": parts,
            "agent": agent
        ]
        if let modelID, !modelID.isEmpty, let providerID, !providerID.isEmpty {
            body["model"] = [
                "providerID": providerID,
                "modelID": modelID
            ]
        }
        if let variant {
            body["variant"] = variant
        }
        if let messageID, !messageID.isEmpty {
            body["messageID"] = messageID
        }
        if let permission, !permission.isEmpty {
            body["permission"] = permission
        }
        for (key, value) in ModelCallParametersStore.requestFragment(parameters) {
            body[key] = value
        }
        return body
    }
}
