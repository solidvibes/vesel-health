import SwiftUI

/// Morning and last night isn't in: the band still records it, or it's 03:00–12:00. One tap ends the night, now or as soon
/// as the Loop is near.
struct GoodMorningCard: View {
    let imUp: () -> Void
    let stillInBed: () -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
                Label {
                    Text("Good morning — I'm up")
                        .font(Theme.Typography.heading)
                        .foregroundStyle(Theme.Palette.text)
                } icon: {
                    Image(systemName: "sun.horizon")
                        .foregroundStyle(Theme.Palette.sleep)
                }
                Text("Tap when you're up, and Vesel gets last night from your Loop.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                Button("I'm up", action: imUp)
                    .buttonStyle(.veselPrimary)
                Button("Still in bed", action: stillInBed)
                    .buttonStyle(.veselSecondary)
            }
        }
    }
}

/// Last night is on its way: "I'm up" waits for the Loop, Polar is finishing the night, or it is being read. Shown where
/// "I'm up" was.
struct EvaluatingNightCard: View {
    /// "I'm up" tried and didn't find the Loop.
    let waitingForLoop: Bool
    /// The morning sleep report is on, so a notification says when it's ready.
    let reportOn: Bool
    /// The Loop ended the night: Polar may take up to 2 hours to finish it, and Vesel checks until then.
    var checksUntil: Date?
    var zone: TimeZone = .current

    private var title: String { checksUntil != nil && !waitingForLoop ? "Polar is finishing your night" : "Evaluating your night" }

    private var message: String {
        if waitingForLoop { return "Nothing for you to do. Your Loop gets the message as soon as it's near your phone." }
        if let checksUntil {
            let ready = reportOn ? " We'll let you know when it's ready." : ""
            return "Your Loop hasn't sent it yet. Vesel checks until \(Formatters.time(checksUntil, zone: zone)).\(ready)"
        }
        return reportOn ? "Nothing for you to do. We'll let you know when it's ready." : "Nothing for you to do. It shows here when it's ready."
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s4) {
                    Text(title)
                        .font(Theme.Typography.heading)
                        .foregroundStyle(Theme.Palette.text)
                    Text(message)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                // A known end time, not endless loading.
                if checksUntil == nil || waitingForLoop {
                    IndeterminateLine(color: Theme.Palette.sleep)
                }
            }
        }
    }
}

/// A read is waiting for the Loop to come near. Calm: nothing is wrong yet.
struct WaitingForLoopCard: View {
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s4) {
                    Text("Waiting for your Loop")
                        .font(Theme.Typography.heading)
                        .foregroundStyle(Theme.Palette.text)
                    Text("Reads as soon as it's near your phone.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                IndeterminateLine(color: Theme.Palette.primary)
            }
        }
    }
}

#if DEBUG
#Preview("I'm up") {
    GoodMorningCard(imUp: {}, stillInBed: {})
        .padding(Theme.Spacing.edge)
        .background { BlobBackground() }
}

#Preview("Evaluating") {
    VStack(spacing: Theme.Spacing.s16) {
        EvaluatingNightCard(waitingForLoop: false, reportOn: true)
        EvaluatingNightCard(waitingForLoop: true, reportOn: false)
        EvaluatingNightCard(waitingForLoop: false, reportOn: true, checksUntil: .now.addingTimeInterval(5400))
        WaitingForLoopCard()
    }
    .padding(Theme.Spacing.edge)
    .background { BlobBackground() }
}
#endif
