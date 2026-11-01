import SwiftUI
import VeselCore

/// Today's steps so far, as the Loop's daily summary counted them when the band was last read. No goal and no comparison.
/// The whole card opens the Steps page.
struct StepsCard: View {
    let steps: Int?
    /// When the band was last read for `steps`.
    let readAt: Date?
    /// Today's steps by hour; empty while it is being read or with none.
    let hours: [HourlySteps.Hour]
    let day: DayKey
    let now: Date
    let zone: TimeZone
    let action: () -> Void

    private static let empty = "No steps yet today"

    var body: some View {
        Button(action: action) {
            GlassCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
                    HStack {
                        Text("Steps")
                            .font(Theme.Typography.label)
                            .foregroundStyle(Theme.Palette.mutedText)
                        Spacer(minLength: Theme.Spacing.s8)
                        Image(systemName: "chevron.right")
                            .font(Theme.Typography.label)
                            .foregroundStyle(Theme.Palette.mutedText)
                    }
                    if let steps {
                        AdaptiveRow(alignment: .firstTextBaseline) {
                            Text(Formatters.steps(steps))
                                .font(Theme.Typography.title)
                                .foregroundStyle(Theme.Palette.text)
                        } trailing: {
                            Text(soFar)
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Palette.mutedText)
                        }
                        if !hours.isEmpty {
                            // To the next whole minute, so the card's refresh leaves the bars alone between minutes.
                            let minute = Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / 60).rounded(.up) * 60)
                            HourlyStepsGlance(hours: hours, day: day, zone: zone, until: minute, height: 44)
                                .allowsHitTesting(false)
                        }
                    } else {
                        Text(Self.empty)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.mutedText)
                    }
                }
                .frame(minHeight: Theme.Size.tapTarget)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Steps")
        .accessibilityValue(steps.map { "\(Formatters.steps($0)), \(soFar)" } ?? Self.empty)
        .accessibilityHint("Opens Steps")
    }

    private var soFar: String {
        readAt.map { "so far · read \(Formatters.clock($0, zone: zone))" } ?? "so far"
    }
}
