import SwiftUI

/// Контекст решения капчи: показывает живой мини-каст вкладки браузера,
/// в которой возникла капча. Пользователь решает её прямо в касте —
/// клики и скролл уходят в браузер через REST `/act/*`.
struct WebCaptchaSolverContext: Identifiable {
    let id = UUID()
    let bridge: AntiBrowserAutomationBridge
    let note: String
}

struct WebCaptchaSolverView: View {
    let context: WebCaptchaSolverContext

    @StateObject private var screencast: ScreencastController

    init(context: WebCaptchaSolverContext) {
        self.context = context
        _screencast = StateObject(wrappedValue: ScreencastController(bridge: context.bridge))
    }

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

            BrowserCastView(screencast: screencast, bridge: context.bridge)
                .frame(minWidth: 720, minHeight: 520)
                .background(Color.mimo.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.mimo.border, lineWidth: 1)
                )
        }
        .padding(20)
        .background(Color.mimo.background)
        .interactiveDismissDisabled(true)
        .onAppear { screencast.start() }
        .onDisappear { screencast.stop() }
    }
}
