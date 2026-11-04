import SwiftUI
import VeselCore

/// One thing that went into recovery: its name, value and mark against your normal. The whole row opens that signal's page.
struct ContributorRow: View {
    let reading: ContributorReading
    let units: Units
    let open: () -> Void

    var body: some View {
        Button(action: open) {
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
                    HStack(spacing: Theme.Spacing.s8) {
                        Text(valueText)
                            .font(Theme.Typography.label)
                            .foregroundStyle(Theme.Palette.text)
                            .multilineTextAlignment(.trailing)
                        if let mark = reading.mark { MarkBadge(mark: mark) }
                    }
                }
            }
            .padding(.vertical, Theme.Spacing.s8)
            .frame(minHeight: Theme.Size.row)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(reading.contributor.title), \(valueText), \(spoken)")
        .accessibilityHint("Opens \(reading.contributor.title)")
    }

    /// Skin temperature as its difference from your usual ("+0.9 °C"); the others as their value.
    private var valueText: String {
        guard reading.contributor == .skinTemperature, reading.mark != nil else { return reading.valueText(units: units) }
        return reading.differenceText(units: units) ?? reading.valueText(units: units)
    }

    private var spoken: String { reading.mark?.words ?? LearningText.nights(reading.nights) }
}
