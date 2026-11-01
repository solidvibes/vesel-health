import SwiftUI
import VeselCore

/// Heart fitness on Body: the band in words with a small still scale. The title opens its meaning; the body, wrapped by `open`, opens `FitnessView`; the title is never inside it.
struct FitnessCard<Open: View>: View {
    let outcome: FitnessOutcome
    let today: DayKey
    let zone: TimeZone
    @ViewBuilder let open: (AnyView) -> Open

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
                FitnessText.title(outcome, zone: zone)
                open(AnyView(content))
            }
        }
    }

    private var content: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.s8) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
                switch outcome {
                case .estimate(let found):
                    Text(found.band.title)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.text)
                    FitnessScale(band: found.band, style: .card)
                    Text(FitnessText.monthLine(found, today: today, zone: zone))
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Palette.mutedText)
                case .learning, .outsideAgeRange:
                    Text(FitnessText.note(outcome, today: today))
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Palette.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Theme.Spacing.s8)
            Image(systemName: "chevron.right")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Palette.mutedText)
                .accessibilityHidden(true)
        }
        .frame(minHeight: Theme.Size.tapTarget)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(FitnessText.spoken(outcome, today: today, zone: zone))
        .accessibilityHint("opens the page")
    }
}

/// The words around heart fitness, shared by the card and the page.
enum FitnessText {
    /// The title that opens what Heart fitness means; with an estimate it carries this month's band and its explanation.
    @MainActor static func title(_ outcome: FitnessOutcome, zone: TimeZone, font: Font = Theme.Typography.heading, isHeader: Bool = false) -> TermTitle {
        guard case .estimate(let found) = outcome else {
            return TermTitle(term: .heartFitness, title: "Heart fitness", font: font, isHeader: isHeader)
        }
        return TermTitle(
            term: .heartFitness, title: "Heart fitness", font: font, isHeader: isHeader,
            yours: "\(month(found, zone: zone)): \(found.band.title.lowercased()).",
            explanations: [("Heart fitness", found.explanation)]
        )
    }

    /// The month the estimate is for: "October".
    static func month(_ found: FitnessEstimate, zone: TimeZone) -> String {
        found.windowEnd.start(in: zone).formatted(Date.FormatStyle(timeZone: zone).month(.wide))
    }

    static func monthLine(_ found: FitnessEstimate, today: DayKey, zone: TimeZone) -> String {
        let worked = DayKey(year: today.year, month: today.month, day: 1).start(in: zone)
        return "\(month(found, zone: zone)) · worked out \(worked.formatted(Date.FormatStyle(timeZone: zone).day().month(.abbreviated)))"
    }

    /// The learning line, or the age-range line.
    static func note(_ outcome: FitnessOutcome, today: DayKey) -> String {
        switch outcome {
        case .outsideAgeRange: "Heart fitness is made for ages 20 to 90."
        default: LearningText.fitness(next: FitnessAge.nextWorkedOut(today: today))
        }
    }

    static func spoken(_ outcome: FitnessOutcome, today: DayKey, zone: TimeZone) -> String {
        switch outcome {
        case .estimate(let found): "\(found.band.spoken), \(monthLine(found, today: today, zone: zone))"
        default: "Heart fitness, \(note(outcome, today: today))"
        }
    }
}
