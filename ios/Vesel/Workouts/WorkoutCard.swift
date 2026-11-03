import SwiftUI
import VeselCore
import VeselStorage

/// Journal's card for one workout: the sport, when, how long and its load, and a small heart-rate line. Opens the Workout page.
struct WorkoutCard: View {
    let labelled: LabelledWorkout
    let zone: TimeZone
    let action: () -> Void

    private var workout: Workout { labelled.workout }

    private var times: String { "\(Formatters.clock(workout.start, zone: zone))–\(Formatters.clock(workout.end, zone: zone))" }

    /// "42 min · load 87"
    private var line: String { ([workout.durationText] + [labelled.load?.shortText].compactMap { $0 }).joined(separator: " · ") }

    /// "Running, 07:10 to 07:52, 42 minutes, cardio load 87"
    private var spoken: String {
        let when = "\(Formatters.clock(workout.start, zone: zone)) to \(Formatters.clock(workout.end, zone: zone))"
        return ([labelled.label.name, when, workout.spokenDuration] + [labelled.load?.spokenText].compactMap { $0 }).joined(separator: ", ")
    }

    private var points: [ReadingPoint] {
        guard let rates = workout.heartRates, rates.intervalMs > 0 else { return [] }
        let step = Double(rates.intervalMs) / 1000
        return rates.bpm.enumerated().map { ReadingPoint(time: workout.start.addingTimeInterval(Double($0.offset) * step), value: Double($0.element)) }
    }

    var body: some View {
        Button(action: action) {
            GlassCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s12) {
                        Image(systemName: WorkoutSymbol.name(labelled.label.sport))
                            .font(Theme.Typography.heading)
                            .foregroundStyle(Theme.Palette.workout)
                        VStack(alignment: .leading, spacing: Theme.Spacing.s4) {
                            Text(labelled.label.name)
                                .font(Theme.Typography.heading)
                                .foregroundStyle(Theme.Palette.text)
                            Text(times)
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Palette.mutedText)
                            Text(line)
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Palette.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: Theme.Spacing.s8)
                        Image(systemName: "chevron.right")
                            .font(Theme.Typography.label)
                            .foregroundStyle(Theme.Palette.mutedText)
                    }
                    let points = points
                    if !points.isEmpty {
                        ReadingLineChart(
                            points: points, domain: workout.start...max(workout.end, workout.start.addingTimeInterval(60)), marks: [], zone: zone,
                            color: Theme.Palette.workout, yDomain: HeartRateCard.fitted(points), height: 44, selection: .constant(nil)
                        )
                        .allowsHitTesting(false)
                    }
                }
                .frame(minHeight: Theme.Size.tapTarget)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityHint("Opens the workout")
    }
}
