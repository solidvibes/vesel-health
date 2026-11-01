import SwiftUI
import VeselCore

/// Heart fitness in full: the band on its scale, the reasons, VO2max (with another device's beside it), the limits and how
/// it's worked out. No age, no change from last month, no comparison verdict.
struct FitnessView: View {
    let outcome: FitnessOutcome
    let measuredVO2max: Double?
    let today: DayKey
    let zone: TimeZone
    let units: Units
    @State private var titleHeight: CGFloat = 0
    @State private var titlePassed = false

    var body: some View {
        ZStack {
            BlobBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.s24) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s4) {
                        FitnessText.title(outcome, zone: zone, font: Theme.Typography.display, isHeader: true)
                            .onGeometryChange(for: CGFloat.self) {
                                $0.size.height
                            } action: {
                                titleHeight = $0
                            }
                            .underBar(titlePassed)
                        if case .estimate(let found) = outcome {
                            Text(FitnessText.monthLine(found, today: today, zone: zone))
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Palette.mutedText)
                        }
                    }
                    switch outcome {
                    case .estimate(let found): estimate(found)
                    case .learning, .outsideAgeRange:
                        GlassCard {
                            Text(FitnessText.note(outcome, today: today))
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Palette.mutedText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.edge)
                .padding(.top, Theme.Spacing.s16)
                .padding(.bottom, Theme.Spacing.s48)
            }
            .onScrollGeometryChange(for: Bool.self) {
                $0.contentOffset.y + $0.contentInsets.top > Theme.Spacing.s16 + titleHeight
            } action: { _, passed in
                titlePassed = passed
            }
            .scrollEdgeEffectStyle(.hard, for: .top)
        }
        .navigationBarTitleDisplayMode(.inline)
        .barTitle("Heart fitness", shown: titlePassed)
    }

    @ViewBuilder private func estimate(_ found: FitnessEstimate) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s20) {
                Text(found.band.title)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                FitnessScale(band: found.band, style: .page)
                VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
                    ForEach(Self.meaning, id: \.self) { line in
                        Text(line)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
                row("Resting heart rate", "\(Formatters.whole(found.restingHeartRate)) bpm")
                Divider()
                row("Exercise days a week", Formatters.whole(found.exerciseDaysPerWeek))
            }
        }
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
                MeaningRow(
                    term: .vo2max, label: "VO2max, Vesel's estimate", value: "about \(Formatters.whole(found.vo2max)) ml/kg/min",
                    yours: "\(FitnessText.month(found, zone: zone)): about \(Formatters.whole(found.vo2max)) ml/kg/min, Vesel's estimate.",
                    explanations: [("VO2max", found.explanation)]
                )
                note("An estimate, often off by 5 or more either way")
                if let measuredVO2max {
                    Divider()
                    row("From your other device", "\(Formatters.whole(measuredVO2max)) ml/kg/min")
                    note(Self.differentMethods)
                }
            }
        }
        VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
            ForEach(Self.limits, id: \.self) { line in
                Text(line)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        HowItsWorkedOutRow(explanations: [found.explanation], lead: bodyLine(found.body))
    }

    /// The body measure the estimate used, said once, where it is worked out.
    private func bodyLine(_ body: FitnessBody) -> String {
        switch body {
        case .waist(let cm):
            "Waist: \(units.waistText(cm: cm)). Waist helps estimate your heart fitness. It stays on this phone."
        case .bmi(let bmi):
            "BMI: \(bmi.formatted(.number.precision(.fractionLength(1)))), from your height and weight. Add your waist in About you and the estimate uses it instead."
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.small)
            .foregroundStyle(Theme.Palette.mutedText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ label: String, _ value: String) -> some View {
        AdaptiveRow {
            Text(label)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.text)
        } trailing: {
            Text(value)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.mutedText)
        }
        .frame(minHeight: Theme.Size.tapTarget)
        .accessibilityElement(children: .combine)
    }

    static let differentMethods =
        "Different methods: your other device works it out from your heart rate during exercise; Vesel estimates from your body, resting heart rate and exercise habits."

    static let meaning = [
        "How your heart compares with other people your age.",
        "A band, not an age: it is an estimate from a population model, not a fitness test.",
        "Worked out once a month; it moves slowly.",
    ]

    static let limits = [
        "Your resting heart rate is measured asleep, so the result leans younger.",
        "Exercise comes from the Loop's moderate and vigorous minutes, not from a questionnaire.",
    ]
}

#if DEBUG
private struct PreviewFitness: View {
    let environment: AppEnvironment
    @State private var model: BodyModel

    init(environment: AppEnvironment) {
        self.environment = environment
        _model = State(initialValue: BodyModel(database: environment.database, clock: environment.clock, units: environment.units, period: .month))
    }

    var body: some View {
        Group {
            if let fitness = model.fitness {
                FitnessView(outcome: fitness, measuredVO2max: model.measuredVO2max, today: model.today, zone: model.zone, units: model.units)
            } else {
                ProgressView()
            }
        }
        .task { await model.observeFitness() }
    }
}

#Preview("Estimate") { PreviewHost { PreviewFitness(environment: $0) } }
#Preview("Learning") { PreviewHost(.firstDay) { PreviewFitness(environment: $0) } }
#endif
