import SwiftUI
import VeselCore

/// "Something's off": what the alert said, and where to look.
struct AlertCard: View {
    let alert: AlertEvent
    let seeWhatChanged: () -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
                Label {
                    Text(alert.title)
                        .font(Theme.Typography.heading)
                        .foregroundStyle(Theme.Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(Theme.Palette.stress)
                }
                Text(alert.body)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                Button("See what changed", action: seeWhatChanged)
                    .buttonStyle(.veselPrimary)
                    .padding(.top, Theme.Spacing.s4)
            }
        }
    }
}

#if DEBUG
#Preview {
    let day = DayKey(year: 2026, month: 10, day: 25)
    let alert = Alert(
        kind: .lowRecovery, day: day, title: "Recovery is low",
        body: "Your last two nights were poor, with a low HRV. Take it easy today.",
        explanation: Explanation(method: "alert.lowRecovery", version: 1, inputs: [], text: "")
    )
    AlertCard(alert: AlertEvent(alert, firedAt: Date(timeIntervalSince1970: 1_792_922_400)), seeWhatChanged: {})
        .padding(Theme.Spacing.edge)
        .background { BlobBackground() }
}
#endif
