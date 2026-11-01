import SwiftUI

/// Glass card with a warning icon, what happened, and one action.
struct ErrorCard: View {
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
    /// One quiet row to where the problem is explained; not a second button.
    var link: (title: String, action: () -> Void)?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
                Label {
                    Text(title)
                        .font(Theme.Typography.heading)
                        .foregroundStyle(Theme.Palette.text)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(Theme.Palette.error)
                }
                Text(message)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                if let link {
                    Button(action: link.action) {
                        HStack {
                            Text(link.title)
                                .font(Theme.Typography.label)
                                .foregroundStyle(Theme.Palette.text)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: Theme.Spacing.s8)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.Palette.mutedText)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: Theme.Size.tapTarget)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.veselPrimary)
                        .padding(.top, Theme.Spacing.s4)
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    VStack(spacing: Theme.Spacing.s16) {
        ErrorCard(
            title: "Setup didn't finish", message: "Your Loop didn't take the settings. Keep it close to your iPhone and try again.", actionTitle: "Try again",
            action: {})
        ErrorCard(
            title: "Can't reach your Loop", message: "Hold it near your iPhone.", actionTitle: "Try again", action: {},
            link: (title: "What to try", action: {})
        )
    }
    .padding(Theme.Spacing.edge)
    .background { BlobBackground() }
}
#endif
