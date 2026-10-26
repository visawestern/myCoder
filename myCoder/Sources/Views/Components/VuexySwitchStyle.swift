import SwiftUI

/// Vuexy-style switch: a green capsule with a white knob. Sized ~30% larger
/// than the system macOS switch so it reads as the primary row control.
struct VuexySwitchStyle: ToggleStyle {
    var onColor: Color = Color.mimo.success
    var offColor: Color = Color.mimo.textMuted.opacity(0.28)
    var width: CGFloat = 44
    var height: CGFloat = 26
    /// Gap between the label and the switch. Icon-only switches use 0 so the
    /// control stays exactly the size of its capsule.
    var labelSpacing: CGFloat = 7

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: labelSpacing) {
            configuration.label
            Button {
                configuration.isOn.toggle()
            } label: {
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? onColor : offColor)
                        .frame(width: width, height: height)
                    Circle()
                        .fill(Color.white)
                        .frame(width: height - 4, height: height - 4)
                        .shadow(color: Color.black.opacity(0.18), radius: 1.5, y: 1)
                        .padding(2)
                }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isOn ? "1" : "0")
        }
        .animation(.easeInOut(duration: 0.16), value: configuration.isOn)
    }
}

extension ToggleStyle where Self == VuexySwitchStyle {
    /// Switch rendered at the size of the old status dot (user directive:
    /// one single control everywhere, no dots next to a bigger switch).
    static var dotSized: VuexySwitchStyle {
        VuexySwitchStyle(width: 20, height: 12, labelSpacing: 0)
    }
}
