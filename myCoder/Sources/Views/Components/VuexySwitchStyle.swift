import SwiftUI

/// Vuexy-style switch: a green capsule with a white knob. Sized ~30% larger
/// than the system macOS switch so it reads as the primary row control.
struct VuexySwitchStyle: ToggleStyle {
    var onColor: Color = Color.mimo.success
    var offColor: Color = Color.mimo.textMuted.opacity(0.28)
    var width: CGFloat = 44
    var height: CGFloat = 26

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 7) {
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
