import Foundation

enum WebDetectionStatusLogic {
    static func statusText(modelCount: Int) -> String {
        modelCount > 0
            ? "myCoder detected \(modelCount) models"
            : "myCoder will detect models after login"
    }
}
