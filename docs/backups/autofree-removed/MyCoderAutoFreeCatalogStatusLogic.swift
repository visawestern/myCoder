import Foundation

enum MyCoderAutoFreeCatalogStatusLogic {
    static let readyMessage = "Anonymous OpenCode free catalog ready."
    static let noModelsMessage = "No free OpenCode models are currently available."

    static func statusAfterRefresh(previousStatus: String,
                                   previousSelectedModel: String,
                                   currentSelectedModel: String,
                                   fetchedModelIDs: [String]) -> String {
        guard !fetchedModelIDs.isEmpty else { return noModelsMessage }
        let switched = previousSelectedModel != currentSelectedModel
            && fetchedModelIDs.contains(currentSelectedModel)
            && previousStatus.localizedCaseInsensitiveContains("switched")
        return switched ? previousStatus : readyMessage
    }
}
