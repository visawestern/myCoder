#if canImport(SwiftUI) && canImport(WebKit)
import SwiftUI
import WebKit

struct WebCaptchaSolverContext: Identifiable {
    let id = UUID()
    let webView: WKWebView
    let note: String
}

struct WebCaptchaSolverView: View {
    let context: WebCaptchaSolverContext

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.t(AppLocalizationKey.locCaptchaVerification))
                .interfaceFont(size: 18, weight: .semibold)
                .foregroundColor(Color.mimo.textPrimary)
            Text(context.note)
                .interfaceFont(size: 13)
                .foregroundColor(Color.mimo.textSecondary)
            Text(L.t(AppLocalizationKey.locCaptchaInstruction))
                .interfaceFont(size: 12)
                .foregroundColor(Color.mimo.textMuted)
            WebChatWebViewHost(webView: context.webView)
                .frame(minWidth: 720, minHeight: 520)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.mimo.border, lineWidth: 1)
                )
        }
        .padding(20)
        .background(Color.mimo.background)
        .interactiveDismissDisabled(true)
    }
}
#endif
