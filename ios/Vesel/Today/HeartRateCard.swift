import SwiftUI
import VeselCore
import VeselStorage
import VeselWearable

/// Today's heart rate: the live bpm (or the latest stored one), last night's resting heart rate and a small line of today so far.
/// The whole card opens the Heart rate page.
struct HeartRateCard: View {
    let live: LiveHeartRate?
    let latest: HeartRateSample?
    let resting: Double?
    /// Today's 5-minute line; empty while it is being read.
    let points: [ReadingPoint]
    /// Today's workouts, drawn behind the line.
    var workouts: [WorkoutSpan] = []
    let day: DayKey
    let now: Date
    let zone: TimeZone
    let action: () -> Void

    private static let empty = "No heart rate yet today"

    var body: some View {
        Button(action: action) {
            GlassCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
                    HStack {
                        Text("Heart rate")
                            .font(Theme.Typography.label)
                            .foregroundStyle(Theme.Palette.mutedText)
                        Spacer(minLength: Theme.Spacing.s8)
                        Image(systemName: "chevron.right")
                            .font(Theme.Typography.label)
                            .foregroundStyle(Theme.Palette.mutedText)
                    }
                    AdaptiveRow(alignment: .firstTextBaseline) {
                        LiveHeartRateText(live: live, latest: latest, zone: zone, empty: Self.empty)
                    } trailing: {
                        if let resting {
                            Text("resting \(Formatters.whole(resting))")
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Palette.mutedText)
                        }
                    }
                    if !soFar.isEmpty {
                        let start = day.start(in: zone)
                        // To the next whole minute, so the card's 1 s refresh leaves the line alone between minutes.
                        let minute = Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / 60).rounded(.up) * 60)
                        let end = max(min(minute, day.adding(days: 1).start(in: zone)), start.addingTimeInterval(3600))
                        SoFarLine(points: soFar, workouts: workouts, domain: start...end, zone: zone)
                            .equatable()
                            .allowsHitTesting(false)
                    }
                }
                .frame(minHeight: Theme.Size.tapTarget)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart rate")
        .accessibilityValue(spoken)
        .accessibilityHint("Opens Heart rate")
    }

    private var soFar: [ReadingPoint] { points.filter { $0.time <= now } }

    static func fitted(_ points: [ReadingPoint]) -> ClosedRange<Double> {
        let values = points.map(\.value)
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let pad = max((high - low) * 0.1, 2)
        return (low - pad)...(high + pad)
    }

    private var spoken: String {
        var parts = [LiveHeartRateText.spoken(live: live, latest: latest, zone: zone, empty: Self.empty)]
        if let resting { parts.append("resting \(Formatters.whole(resting)) bpm") }
        if let low = soFar.map(\.value).min(), let high = soFar.map(\.value).max() {
            parts.append("today so far \(Formatters.whole(low)) to \(Formatters.whole(high)) bpm")
        }
        parts += workouts.map { "\($0.word) from \(Formatters.clock($0.range.lowerBound, zone: zone)) to \(Formatters.clock($0.range.upperBound, zone: zone))" }
        return parts.joined(separator: ", ")
    }
}

/// Today's line so far; redrawn only when its points or its end change.
private struct SoFarLine: View, Equatable {
    let points: [ReadingPoint]
    let workouts: [WorkoutSpan]
    let domain: ClosedRange<Date>
    let zone: TimeZone

    var body: some View {
        ReadingLineChart(
            points: points, domain: domain, marks: [], zone: zone, color: Theme.Palette.recovery, workouts: workouts,
            yDomain: HeartRateCard.fitted(points), height: 44, selection: .constant(nil)
        )
    }
}
