import SwiftUI
import VeselCore
import VeselStorage

/// Under the Steps card: one short glass row per workout started today, "Cycling · 07:10 · 24 min · load 172", each opening the
/// Workout page. Nothing with none.
struct WorkoutLines: View {
    let workouts: [LabelledWorkout]
    let zone: TimeZone
    let open: (WorkoutRoute) -> Void

    var body: some View {
        ForEach(workouts, id: \.workout.session) { labelled in
            let workout = labelled.workout
            let start = Formatters.clock(workout.start, zone: zone)
            let line = ([labelled.label.name, start, workout.durationText] + [labelled.load?.shortText].compactMap { $0 }).joined(separator: " · ")
            let spoken = ([labelled.label.name, "at \(start)", workout.spokenDuration] + [labelled.load?.spokenText].compactMap { $0 })
                .joined(separator: ", ")
            Button {
                open(WorkoutRoute(session: workout.session))
            } label: {
                HStack(spacing: Theme.Spacing.s12) {
                    Image(systemName: WorkoutSymbol.name(labelled.label.sport))
                        .foregroundStyle(Theme.Palette.workout)
                    Text(line)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Theme.Spacing.s8)
                    Image(systemName: "chevron.right")
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Palette.mutedText)
                }
                .padding(.horizontal, Theme.Spacing.s20)
                .padding(.vertical, Theme.Spacing.s12)
                .frame(maxWidth: .infinity, minHeight: Theme.Size.tapTarget, alignment: .leading)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Theme.Corner.card))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
            .accessibilityHint("Opens the workout")
        }
    }
}
