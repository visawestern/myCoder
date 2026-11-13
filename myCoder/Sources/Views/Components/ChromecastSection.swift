import SwiftUI

/// Right-sidebar CHROMECAST section: a collapsible spoiler with a live
/// picture-in-picture thumbnail of the built-in browser.
///
/// The screenshot loop is owned by `WebBrowserCastStore` and is NOT stopped
/// when this spoiler is closed or when the chat browser panel is hidden, so
/// the picture stays live and re-opening the spoiler is instant.
///
/// Input: the visible browser panel (if any) and the always-on cast tab.
/// Output: a collapsed header, or a 16:9 live thumbnail that opens the browser.
/// Dependencies: `WebBrowserCastLogic` for tab/PiP rules.
struct ChromecastSection: View {
    @EnvironmentObject var appState: AppState
    /// Spoiler starts collapsed: the right panel stays compact until asked.
    @State private var isExpanded = false

    private var config: WebBrowserPanelConfig? {
        WebBrowserCastLogic.displayConfig(
            panelConfig: appState.webBrowserPanelConfig,
            castConfig: appState.webBrowserCast.config
        )
    }

    var body: some View {
        if let config {
            VStack(alignment: .leading, spacing: 8) {
                header(config)
                if isExpanded {
                    ChromecastThumbnail(store: appState.webBrowserCast,
                                        config: config) {
                        appState.openWebBrowserPanel(config)
                    }
                }
            }
            .padding(16)
            .task(id: config) {
                // Safety net: the store normally starts the cast when the web
                // turn begins, but the section must never show a dead image.
                appState.webBrowserCast.activate(config)
            }
        }
    }

    /// Spoiler header: one click expands/collapses the live image.
    ///
    /// - Parameter config: tab currently cast.
    private func header(_ config: WebBrowserPanelConfig) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .interfaceFont(size: 12, weight: .semibold)
                    .foregroundColor(Color.mimo.cyan)
                Text(L.t(AppLocalizationKey.locChromecast))
                    .interfaceFont(size: 12, weight: .semibold)
                    .foregroundColor(Color.mimo.textPrimary)
                Text(config.providerName)
                    .interfaceFont(size: 10)
                    .foregroundColor(Color.mimo.textMuted)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .interfaceFont(size: 9, weight: .semibold)
                    .foregroundColor(Color.mimo.textMuted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(HandCursorButtonStyle())
        .help(L.t(AppLocalizationKey.locChromecastHint))
        .accessibilityLabel(L.t(AppLocalizationKey.locChromecast))
        .accessibilityValue(isExpanded ? "expanded" : "collapsed")
    }
}

/// The PiP image itself. Observing only the store keeps 3 FPS frame updates
/// from re-rendering the whole right panel.
private struct ChromecastThumbnail: View {
    @ObservedObject var store: WebBrowserCastStore
    let config: WebBrowserPanelConfig
    let onOpen: () -> Void

    private var size: CGSize {
        WebBrowserCastLogic.thumbnailSize(width: 220)
    }

    var body: some View {
        Button(action: onOpen) {
            ZStack {
                if store.config == config,
                   let screencast = store.controller,
                   let bridge = store.bridge {
                    BrowserCastView(screencast: screencast, bridge: bridge)
                        // The thumbnail is a preview, not a second input
                        // surface: a click opens the real browser panel.
                        .allowsHitTesting(false)
                } else {
                    placeholder
                }
            }
            .frame(width: size.width, height: size.height)
            .background(Color.black.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.mimo.cyan.opacity(0.55), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 2)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(HandCursorButtonStyle())
        .help(L.t(AppLocalizationKey.locBrowserShow))
    }

    private var placeholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "globe")
                .interfaceFont(size: 18)
                .foregroundColor(Color.mimo.cyan.opacity(0.7))
            ProgressView()
                .scaleEffect(0.6)
        }
    }
}
