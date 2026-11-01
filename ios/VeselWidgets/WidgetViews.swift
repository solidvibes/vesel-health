import SwiftUI
import VeselCore
import VeselStorage
import WidgetKit

extension View {
    /// A stale snapshot is shown dimmed.
    func dimmed(_ stale: Bool) -> some View {
        opacity(stale ? 0.55 : 1)
    }
}

/// "No data yet": the same words in every widget size.
struct NoDataFace: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.s4) {
            Image(systemName: "moon.zzz")
                .font(.title2)
                .foregroundStyle(Theme.Palette.mutedText)
            Text("No data yet")
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Palette.text)
            Text("Fills in after your first night with the Loop.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Palette.mutedText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// One range line with its name and value, sized for a widget. While learning there is no line; the widget says so.
struct WidgetLine: View {
    enum Layout {
        /// Name above a large value, then the line.
        case card
        /// Name left and value right, the line under them.
        case stacked
        /// Name, line and value on one row.
        case inline
    }

    let title: String
    let valueText: String
    let verdict: LineVerdict
    let color: Color
    var layout: Layout = .stacked
    var lineHeight: CGFloat = 10

    var body: some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(verdict.state.spokenValue(valueText))
    }

    private var line: some View {
        RangeLine(scale: verdict.scale, outside: verdict.state.isOutside, color: color, height: lineHeight)
    }

    @ViewBuilder private var content: some View {
        switch layout {
        case .card:
            VStack(alignment: .leading, spacing: Theme.Spacing.s4) {
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.Palette.mutedText)
                Text(valueText)
                    .font(.title2.bold())
                    .foregroundStyle(Theme.Palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !verdict.state.isLearning { line.padding(.top, Theme.Spacing.s4) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .stacked:
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: Theme.Spacing.s4)
                    Text(valueText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if !verdict.state.isLearning { line }
            }
        case .inline:
            HStack(spacing: Theme.Spacing.s8) {
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.Palette.mutedText)
                    .frame(width: 56, alignment: .leading)
                if verdict.state.isLearning { Spacer(minLength: 0) } else { line }
                Text(valueText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: 72, alignment: .trailing)
            }
        }
    }
}

extension VeselEntry {
    var recoveryWord: String { snapshot.status?.word.capitalizedFirst ?? "—" }
    var sleepText: String { snapshot.asleepMinutes.map { DurationText.hoursMinutes(minutes: $0) } ?? "—" }
    var recoveryColor: Color { Theme.Palette.recoveryLine(snapshot.status) }

    /// "Your usual range appears after 7 nights · 3 of 7" while there are fewer than 7 earlier nights.
    var learningText: String? {
        guard case .learning(let nights) = content else { return nil }
        return LearningText.nights(nights)
    }
}
