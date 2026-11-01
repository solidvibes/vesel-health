import SwiftUI
import VeselCore

/// A list row whose whole width opens a term's meaning, in place of expanding: label, value, chevron.
struct MeaningRow: View {
    let term: Term
    let label: String
    let value: String
    var yours: String?
    var explanations: [(label: String, explanation: Explanation)] = []
    @Environment(\.showMeaning) private var showMeaning

    var body: some View {
        Button {
            showMeaning(MeaningRequest(term: term, yours: yours, explanations: explanations))
        } label: {
            HStack(spacing: Theme.Spacing.s12) {
                AdaptiveRow {
                    Text(label)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.text)
                } trailing: {
                    Text(value)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.mutedText)
                        .multilineTextAlignment(.trailing)
                }
                Image(systemName: "chevron.right")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Theme.Size.row)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label), \(value), what it means")
    }
}
