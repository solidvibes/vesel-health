import SwiftUI

/// Outline icon, a one-line title, one line on what happens next.
struct EmptyState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        GlassCard {
            VStack(spacing: Theme.Spacing.s12) {
                Image(systemName: systemImage)
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(Theme.Palette.mutedText)
                    .accessibilityHidden(true)
                Text(title)
                    .font(Theme.Typography.heading)
                    .foregroundStyle(Theme.Palette.text)
                Text(message)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.mutedText)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.s16)
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview {
    EmptyState(systemImage: "moon", title: "No sleep for this night", message: "Polar hasn't finished it yet; it fills in on the next read.")
        .padding(Theme.Spacing.edge)
        .background { BlobBackground() }
}
#endif
