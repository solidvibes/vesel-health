import SwiftUI
import VeselCore

/// "How it's worked out": the sentence, then the method and its version.
struct ExplanationView: View {
    let explanation: Explanation

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s4) {
            Text(explanation.text)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            Text("Method \(explanation.method), version \(explanation.version)")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Palette.mutedText)
        }
    }
}

/// A list row that opens its own explanation when tapped.
struct ExplainedRow: View {
    let label: String
    let value: String
    let explanation: Explanation?
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                guard explanation != nil else { return }
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { expanded.toggle() }
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
                    if explanation != nil {
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                            .font(Theme.Typography.small)
                            .foregroundStyle(Theme.Palette.mutedText)
                            .accessibilityHidden(true)
                    }
                }
                .frame(minHeight: Theme.Size.row)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(explanation == nil ? "" : "Shows how it's worked out")
            VStack(alignment: .leading, spacing: 0) {
                if expanded, let explanation {
                    ExplanationView(explanation: explanation)
                        .padding(.vertical, Theme.Spacing.s8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
    }
}
