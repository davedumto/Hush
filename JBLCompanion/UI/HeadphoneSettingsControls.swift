import SwiftUI

/// Max Volume Limiter / Voice Prompt toggles — in-tray, same pattern as IslandSettingsControls/
/// EqualizerControls (owner request, 2026-10-22: new captures for both, "add the settings to the
/// tray"). Each row only shows once its own DeviceToggle is hardware-verified for the connected
/// profile (DeviceToggle's own doc comment covers what's verified and the confirmation strength
/// for each); neither gates the other, since they're independent settings with independent
/// verification.
struct HeadphoneSettingsControls: View {
    let canUseMaxVolumeLimiter: Bool
    let maxVolumeLimiterOn: Bool
    let onSetMaxVolumeLimiter: (Bool) -> Void
    let canUseVoicePrompt: Bool
    let voicePromptOn: Bool
    let onSetVoicePrompt: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if canUseMaxVolumeLimiter {
                row(title: "Max Volume Limiter", isOn: maxVolumeLimiterOn, onSet: onSetMaxVolumeLimiter)
            }
            if canUseVoicePrompt {
                row(title: "Voice Prompt", isOn: voicePromptOn, onSet: onSetVoicePrompt)
            }
            if !canUseMaxVolumeLimiter && !canUseVoicePrompt {
                Text("Headphone settings aren't verified for this model yet.")
                    .font(Theme.Fonts.subText)
                    .foregroundStyle(Theme.Semantic.textSecondary)
            }
        }
    }

    private func row(title: String, isOn: Bool, onSet: @escaping (Bool) -> Void) -> some View {
        HStack {
            Text(title)
                .font(Theme.Fonts.subText)
                .foregroundStyle(Theme.Semantic.textPrimary)
            Spacer()
            OrangeToggle(isOn: Binding(get: { isOn }, set: { onSet($0) }))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.Semantic.glassFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.Semantic.glassStroke, lineWidth: 1))
    }
}
