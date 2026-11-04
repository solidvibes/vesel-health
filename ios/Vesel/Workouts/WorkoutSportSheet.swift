import SwiftUI
import VeselCore

/// The owner's fix: one of their sports, or "Not a workout" (hides it everywhere). The choice stays through later reads.
struct WorkoutSportSheet: View {
    let sports: [WorkoutSport]
    /// The sport the owner already chose, if any.
    let current: WorkoutSport?
    let choose: (WorkoutSport) -> Void
    let notAWorkout: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            ZStack {
                BlobBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s20) {
                        Text("What was it?")
                            .font(Theme.Typography.title)
                            .foregroundStyle(Theme.Palette.text)
                            .accessibilityAddTraits(.isHeader)
                        GlassCard {
                            VStack(spacing: 0) {
                                ForEach(Array(sports.enumerated()), id: \.element) { index, sport in
                                    if index > 0 { Divider() }
                                    Button {
                                        choose(sport)
                                        dismiss()
                                    } label: {
                                        HStack(spacing: Theme.Spacing.s12) {
                                            Image(systemName: WorkoutSymbol.name(sport))
                                                .foregroundStyle(Theme.Palette.workout)
                                                .frame(width: 28)
                                                .accessibilityHidden(true)
                                            Text(sport.name)
                                                .font(Theme.Typography.body)
                                                .foregroundStyle(Theme.Palette.text)
                                            Spacer(minLength: Theme.Spacing.s8)
                                            if sport == current {
                                                Image(systemName: "checkmark")
                                                    .foregroundStyle(Theme.Palette.text)
                                                    .accessibilityHidden(true)
                                            }
                                        }
                                        .frame(minHeight: Theme.Size.row)
                                        .contentShape(.rect)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityAddTraits(sport == current ? .isSelected : [])
                                }
                            }
                        }
                        Button("Not a workout", role: .destructive) {
                            notAWorkout()
                            dismiss()
                        }
                        .buttonStyle(.veselSecondary)
                        Text("Not a workout hides it everywhere, and its time counts for stress again. Your choice stays when the Loop is read again.")
                            .font(Theme.Typography.small)
                            .foregroundStyle(Theme.Palette.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, Theme.Spacing.edge)
                    .padding(.top, Theme.Spacing.s8)
                    .padding(.bottom, Theme.Spacing.s32)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
    }
}

/// The SF Symbol for a sport; a mixed one for "Workout".
enum WorkoutSymbol {
    static func name(_ sport: WorkoutSport?) -> String {
        switch sport {
        case .running: "figure.run"
        case .cycling: "figure.outdoor.cycle"
        case .swimming: "figure.pool.swim"
        case .strength: "figure.strengthtraining.traditional"
        case nil: "figure.mixed.cardio"
        }
    }
}

#if DEBUG
#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        WorkoutSportSheet(sports: WorkoutSport.allCases, current: .cycling, choose: { _ in }, notAWorkout: {})
    }
}
#endif
