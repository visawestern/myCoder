import SwiftUI
import Foundation

/// Shows the FULL prompt of a goal — the goal, its plan, the continuation
/// instruction and the devil's-advocate verification prompt (user directive
/// 2026-11-08). The prompt is taller than the visible window by design, so
/// it scrolls inside its own frame instead of pushing the panel away.
///
/// `GoalPromptPresentation.visibleLineLimit` (10) is the height cue: when
/// the prompt is shorter the scroll area collapses to its natural size.
struct GoalPromptView: View {
    let text: String
    let language: AppLanguage

    private var presentation: GoalPromptPresentation {
        GoalPromptPresentation(text: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "doc.text.magnifyingglass")
                    .interfaceFont(size: 10)
                    .foregroundColor(Color.mimo.textMuted)
                Text(L.t(AppLocalizationKey.locGoalFullPrompt))
                    .interfaceFont(size: 10, weight: .medium)
                    .foregroundColor(Color.mimo.textSecondary)
            }
            if presentation.exceedsVisibleLines {
                ScrollView {
                    Text(text)
                        .interfaceFont(size: 10)
                        .foregroundColor(Color.mimo.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(height: scrollHeight)
            } else {
                Text(text)
                    .interfaceFont(size: 10)
                    .foregroundColor(Color.mimo.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Ten wrapped lines at the panel's type size.
    private var scrollHeight: CGFloat {
        CGFloat(GoalPromptPresentation.visibleLineLimit) * 16
    }
}
