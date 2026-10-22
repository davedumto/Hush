import SwiftUI

/// A hand-drawn capsule toggle, not `.toggleStyle(.switch).tint(...)` — owner-reported: the system
/// switch didn't actually turn orange when on (AppKit's switch tint only colors the thumb's own
/// tracking ring on some macOS versions, not the track fill), so every toggle in the card (Island
/// Settings' "Auto-expand on connect"/"Launch at Login", the Equalizer's on/off) shares this one
/// implementation instead of depending on a system style's own tint behavior per toggle.
struct OrangeToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Capsule()
                .fill(isOn ? AnyShapeStyle(Theme.Brand.orange) : AnyShapeStyle(Theme.Semantic.glassFill))
                .overlay(Capsule().strokeBorder(isOn ? Color.clear : Theme.Semantic.glassStroke, lineWidth: 1))
                .frame(width: 40, height: 24)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 18, height: 18)
                        .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
                        .padding(3)
                }
                .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isOn)
        }
        .buttonStyle(.plain)
    }
}
