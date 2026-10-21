import SwiftUI
import os.log

/// "Report a Bug / Suggest a Feature…" window, opened from the fallback menu
/// (AppDelegate.reportBugFromFallback → NotchPanel.requestOpenFeedback() → NotchView's own
/// openWindow call — see IslandSettingsView's doc comment for why it can't be called directly
/// from AppDelegate). Posts to the hush-feedback backend over plain HTTPS; nothing here touches
/// Bluetooth, WriteGuard, or any RFCOMM/BLE code — it only *reads* diagnostics text that already
/// exists for "Copy Diagnostics".
struct FeedbackView: View {
    static let windowID = "feedback"

    let appDelegate: AppDelegate

    @State private var type: FeedbackType = .bug
    @State private var title: String = ""
    @State private var whatHappened: String = ""
    @State private var steps: String = ""
    @State private var expected: String = ""
    @State private var featureDescription: String = ""
    @State private var replyEmail: String = ""
    @State private var includeDiagnostics: Bool = true

    @State private var isSubmitting = false
    @State private var statusMessage: String?
    @State private var didSucceed = false

    @Environment(\.dismiss) private var dismiss

    private let logger = Logger(subsystem: "com.davidejere.JBLCompanion", category: "FeedbackView")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                typeSwitcher
                labeledField("Title") {
                    glassTextField("A short summary", text: $title)
                }

                if type == .bug {
                    labeledField("What happened") {
                        glassTextEditor(text: $whatHappened, minHeight: 60)
                    }
                    labeledField("Steps to reproduce") {
                        glassTextEditor(text: $steps, minHeight: 60)
                    }
                    labeledField("What you expected instead") {
                        glassTextEditor(text: $expected, minHeight: 60)
                    }
                } else {
                    labeledField("Describe the feature") {
                        glassTextEditor(text: $featureDescription, minHeight: 100)
                    }
                }

                labeledField("Reply email (optional)") {
                    glassTextField("you@example.com", text: $replyEmail)
                }

                Toggle("Include diagnostics", isOn: $includeDiagnostics)
                    .toggleStyle(.switch)
                    .tint(Theme.Brand.orange)
                    .font(Theme.Fonts.subText)
                    .foregroundStyle(Theme.Semantic.textPrimary)

                Text("Diagnostics include link/connection state, never Bluetooth addresses or anything that identifies you.")
                    .font(Theme.Fonts.statusDetail)
                    .foregroundStyle(Theme.Semantic.textSecondary)

                if let statusMessage {
                    Text(statusMessage)
                        .font(Theme.Fonts.statusModeName)
                        .foregroundStyle(didSucceed ? .green : Theme.Brand.orange)
                }

                submitButton
            }
            .padding(22)
        }
        .frame(width: 420, height: 580)
        .background(panelGradient)
        .background(Theme.Semantic.cardFrame)
    }

    private var header: some View {
        Text(type == .bug ? "Report a Bug" : "Suggest a Feature")
            .font(.custom("Fredoka-SemiBold", size: 19))
            .foregroundStyle(Theme.Semantic.textPrimary)
    }

    private var typeSwitcher: some View {
        HStack(spacing: 6) {
            typeSwitcherButton("Bug", isSelected: type == .bug) { type = .bug }
            typeSwitcherButton("Feature", isSelected: type == .feature) { type = .feature }
        }
    }

    private func typeSwitcherButton(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Theme.Fonts.modeLabel())
                .foregroundStyle(isSelected ? Theme.Semantic.pillInk : Theme.Semantic.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isSelected ? AnyShapeStyle(Theme.Brand.orange) : AnyShapeStyle(Theme.Semantic.glassFill), in: Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? Color.clear : Theme.Semantic.glassStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func labeledField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(Theme.Fonts.eyebrow)
                .foregroundStyle(Theme.Semantic.textSecondary)
            content()
        }
    }

    private func glassTextField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(Theme.Fonts.subText)
            .foregroundStyle(Theme.Semantic.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Theme.Semantic.glassFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.Semantic.glassStroke, lineWidth: 1))
    }

    private func glassTextEditor(text: Binding<String>, minHeight: CGFloat) -> some View {
        TextEditor(text: text)
            .scrollContentBackground(.hidden)
            .font(Theme.Fonts.subText)
            .foregroundStyle(Theme.Semantic.textPrimary)
            .frame(minHeight: minHeight)
            .padding(8)
            .background(Theme.Semantic.glassFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.Semantic.glassStroke, lineWidth: 1))
    }

    private var submitButton: some View {
        Button {
            if didSucceed {
                dismiss()
            } else {
                submit()
            }
        } label: {
            HStack {
                Spacer()
                if isSubmitting {
                    ProgressView().controlSize(.small)
                } else {
                    Text(didSucceed ? "Done" : "Submit")
                        .font(Theme.Fonts.statusModeName)
                        .foregroundStyle(Theme.Semantic.pillInk)
                }
                Spacer()
            }
            .padding(.vertical, 10)
            .background(Theme.Brand.orange, in: Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        .disabled(isSubmitting || (!didSucceed && !canSubmit))
        .opacity(isSubmitting || (!didSucceed && !canSubmit) ? 0.5 : 1)
    }

    /// Same radial gradient as ExpandedCard's own panel fill — design/DESIGN_GUIDE.md §4 "Panel
    /// fill" — so this window reads as part of the same system instead of a bare macOS sheet.
    private var panelGradient: RadialGradient {
        RadialGradient(
            gradient: Gradient(stops: [
                .init(color: Theme.Semantic.panelHighlight, location: 0),
                .init(color: Theme.Semantic.panelBase, location: 0.56),
                .init(color: Theme.Semantic.panelEdge, location: 1),
            ]),
            center: UnitPoint(x: 0.5, y: 0.28),
            startRadius: 0, endRadius: 580
        )
    }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (type == .bug ? !whatHappened.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              : !featureDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func submit() {
        let description = FeedbackDescription(
            whatHappened: type == .bug ? whatHappened : nil,
            steps: type == .bug ? steps : nil,
            expected: type == .bug ? expected : nil,
            featureDescription: type == .feature ? featureDescription : nil
        )

        let request: FeedbackRequest
        do {
            request = try FeedbackRequestBuilder.build(
                type: type,
                title: title,
                description: description,
                replyEmail: replyEmail,
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
                macosVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                macModel: Self.macModelIdentifier(),
                profileName: appDelegate.currentProfileDisplayName,
                locale: Locale.current.identifier,
                diagnostics: includeDiagnostics ? appDelegate.diagnosticsText() : nil,
                clientUuid: FeedbackClient.shared.clientUUID
            )
        } catch {
            statusMessage = Self.message(for: error)
            didSucceed = false
            return
        }

        isSubmitting = true
        statusMessage = nil
        Task {
            let result = await FeedbackClient.shared.submit(request)
            isSubmitting = false
            switch result {
            case .success:
                didSucceed = true
                statusMessage = "Thanks — sent."
            case .rejected(let message):
                didSucceed = false
                statusMessage = message
            case .rateLimited(let retryAfterSeconds):
                didSucceed = false
                if let retryAfterSeconds {
                    let minutes = max(1, retryAfterSeconds / 60)
                    statusMessage = "Too many reports recently — try again in about \(minutes) minute\(minutes == 1 ? "" : "s")."
                } else {
                    statusMessage = "Too many reports recently — try again later."
                }
            case .networkError:
                didSucceed = false
                statusMessage = "Couldn't reach the server. Check your connection and try again."
            }
        }
    }

    private static func message(for error: Error) -> String {
        guard let validationError = error as? FeedbackValidationError else { return "Something went wrong." }
        switch validationError {
        case .emptyTitle: return "Please add a title."
        case .emptyDescription: return "Please describe what happened."
        case .invalidReplyEmail: return "That doesn't look like a valid email address."
        }
    }

    private static func macModelIdentifier() -> String? {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
