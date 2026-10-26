import Foundation
import Testing
@testable import myCoder

@Suite("SID-15: notification action routing")
struct NotificationActionRoutingLogicTests {
    @Test("supported actions dismiss after successful routing")
    func supportedActionsDismiss() {
        #expect(NotificationActionRoutingLogic.shouldDismissSheet(after: .openSession("session"), sessionWasFound: true))
        #expect(NotificationActionRoutingLogic.shouldDismissSheet(after: .openSettings, sessionWasFound: false))
        #expect(NotificationActionRoutingLogic.shouldDismissSheet(after: .openGit, sessionWasFound: false))
    }

    @Test("missing session and custom no-op actions do not dismiss")
    func failedOrUnsupportedActionsStayOpen() {
        #expect(!NotificationActionRoutingLogic.shouldDismissSheet(after: .openSession("missing"), sessionWasFound: false))
        #expect(!NotificationActionRoutingLogic.shouldDismissSheet(after: .custom("unknown"), sessionWasFound: true))
    }

    @Test("action handlers always mark the notification read before routing")
    func actionMarksRead() {
        #expect(NotificationActionRoutingLogic.shouldMarkReadBeforeRouting)
    }
}
