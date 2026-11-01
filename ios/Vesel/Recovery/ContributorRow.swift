import SwiftUI
import VeselCore

/// One thing that went into recovery, in words against your usual. The whole row opens its meaning; the chart is one tap further ("Night by night").
struct ContributorRow: View {
    let reading: ContributorReading
    /// "Last night: 48 ms, higher than your usual (34–52 ms)."
    let yours: String
    let units: Units
    let nightByNight: () -> Void
    @Environment(\.showMeaning) private var showMeaning

    var body: some View {
        Button {
            showMeaning(
                MeaningRequest(
                    term: term, yours: yours,
                    explanations: [(reading.contributor.title, reading.explanation)],
                    more: ("Night by night", nightByNight)
                ))
        } label: {
            HStack(spacing: Theme.Spacing.s12) {
                AdaptiveRow {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s4) {
                        Text(reading.contributor.title)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.text)
                        if reading.range == nil {
                            Text(LearningText.nights(reading.nights))
                                .font(Theme.Typography.small)
                                .foregroundStyle(Theme.Palette.mutedText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } trailing: {
                    Label {
                        Text(trailingText).foregroundStyle(Theme.Palette.text)
                    } icon: {
                        Image(systemName: arrow).foregroundStyle(color)
                    }
                    .font(Theme.Typography.label)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Image(systemName: "chevron.right")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, Theme.Spacing.s8)
            .frame(minHeight: Theme.Size.row)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(reading.contributor.title), \(spoken), what it means")
    }

    private var term: Term {
        switch reading.contributor {
        case .hrv: .hrv
        case .restingHeartRate: .restingHeartRate
        case .sleep: .sleepTime
        case .breathing: .breathing
        case .skinTemperature: .skinTemperature
        }
    }

    /// "higher than usual · 48 ms"; skin temperature "usual · +0.2 °C"; while learning, just the value.
    private var trailingText: String {
        let value =
            reading.contributor == .skinTemperature
            ? (reading.differenceText(units: units) ?? reading.valueText(units: units)) : reading.valueText(units: units)
        guard let word = reading.verdictWord else { return value }
        return "\(word) · \(value)"
    }

    private var spoken: String {
        let words = trailingText.replacingOccurrences(of: " · ", with: ", ")
        return reading.range == nil ? "\(words), \(LearningText.nights(reading.nights))" : words
    }

    private var color: Color {
        switch reading.contributor.goodSide(of: reading.verdict) {
        case .good: Theme.Palette.success
        case .other: Theme.Palette.stress
        case .none: Theme.Palette.mutedText
        }
    }

    private var arrow: String {
        switch reading.verdict {
        case .wellBelow, .lower: "arrow.down.right"
        case .higher, .wellAbove: "arrow.up.right"
        case .usual, .learning: "arrow.right"
        }
    }
}
