import Foundation
import CoreGraphics
import SwiftUI

/// Pure rules for the always-on browser cast (CHROMECAST).
///
/// The cast is not tied to panel visibility: once a tab is known it keeps
/// streaming, so the right-panel PiP thumbnail stays live even while the chat
/// panel is hidden. These helpers decide which tab is displayed, when the
/// screenshot loop must move to another tab, and the PiP geometry.
///
/// Dependencies: CoreGraphics for CGFloat and the tab-key builder. No UI
/// state, no networking — fully testable.
enum WebBrowserCastLogic {
    /// 16:9, the natural shape of a browser viewport.
    static let thumbnailAspectRatio: CGFloat = 16.0 / 9.0

    /// The tab the CHROMECAST thumbnail should show.
    ///
    /// The visible panel wins (the user is looking at that tab). With the
    /// panel hidden, the last cast tab remains — this is what keeps the PiP
    /// alive after "hide browser".
    ///
    /// - Parameters:
    ///   - panelConfig: visible browser panel, nil when hidden.
    ///   - castConfig: tab the running screencast belongs to.
    /// - Returns: the tab to display, or nil when nothing was ever cast.
    static func displayConfig(
        panelConfig: WebBrowserPanelConfig?,
        castConfig: WebBrowserPanelConfig?
    ) -> WebBrowserPanelConfig? {
        panelConfig ?? castConfig
    }

    /// Whether the screenshot loop should be running.
    ///
    /// - Parameter castConfig: tab the screencast belongs to.
    /// - Returns: true whenever a tab is known, even if the panel is hidden.
    static func shouldCast(castConfig: WebBrowserPanelConfig?) -> Bool {
        castConfig != nil
    }

    /// Whether the store must replace its screencast controller.
    ///
    /// - Parameters:
    ///   - current: tab of the running controller.
    ///   - requested: tab the caller wants now (nil = stop).
    /// - Returns: true when the controller must be stopped/recreated.
    static func needsNewController(
        current: WebBrowserPanelConfig?,
        requested: WebBrowserPanelConfig?
    ) -> Bool {
        current != requested
    }

    /// PiP thumbnail size for a given sidebar width.
    ///
    /// - Parameter width: thumbnail width in points.
    /// - Returns: 16:9 size.
    static func thumbnailSize(width: CGFloat) -> CGSize {
        CGSize(width: width, height: width / thumbnailAspectRatio)
    }

    /// AntiBrowser tab key of a panel config.
    ///
    /// - Parameter config: provider/project/chat identity.
    /// - Returns: the same key the chat bridge uses.
    static func tabKey(for config: WebBrowserPanelConfig) -> String {
        AntiBrowserTabManager.makeKey(
            providerID: config.providerID,
            projectID: config.projectID,
            chatID: config.chatID
        )
    }
}

/// Owns the ONE always-on screencast of the active browser tab.
///
/// Both the chat's browser panel and the right-sidebar CHROMECAST thumbnail
/// render this controller, so a tab is never polled twice. Hiding the panel
/// does not stop the loop: only switching to another tab (or app teardown)
/// replaces it.
@MainActor
final class WebBrowserCastStore: ObservableObject {
    /// Tab the running screencast belongs to.
    @Published private(set) var config: WebBrowserPanelConfig?
    /// Live frame source shared by every cast view.
    @Published private(set) var controller: ScreencastController?
    /// Input bridge of the same tab (used by the interactive chat panel).
    @Published private(set) var bridge: AntiBrowserAutomationBridge?

    /// Point the always-on cast at `requested`, reusing the controller when
    /// the tab did not change.
    ///
    /// - Parameter requested: tab to cast; nil stops the loop.
    func activate(_ requested: WebBrowserPanelConfig?) {
        guard WebBrowserCastLogic.needsNewController(current: config, requested: requested) else {
            return
        }
        controller?.stop()
        config = requested
        guard let requested else {
            controller = nil
            bridge = nil
            return
        }
        let tabBridge = AntiBrowserTabManager.shared.bridge(
            tabKey: WebBrowserCastLogic.tabKey(for: requested)
        )
        let next = ScreencastController(bridge: tabBridge)
        next.start()
        bridge = tabBridge
        controller = next
    }
}
