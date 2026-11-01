import SwiftUI
import VeselCore
import VeselStorage
import WidgetKit

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.vesel.ios.today", provider: Provider()) { entry in
            TodayWidgetView(entry: entry)
                .widgetURL(URL(string: "vesel://today"))
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("Today")
        .description("How you are today, with Recovery, Sleep and Stress.")
        .supportedFamilies([.systemMedium])
    }
}

struct TodayWidgetView: View {
    let entry: VeselEntry

    var body: some View {
        if entry.content == .noData {
            NoDataFace()
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s4) {
                    Text(entry.snapshot.headline?.sentence ?? "Last night is in.")
                        .font(Theme.Typography.heading)
                        .foregroundStyle(Theme.Palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let why = entry.snapshot.headline?.why, !why.isEmpty {
                        Text(why)
                            .font(Theme.Typography.small)
                            .foregroundStyle(Theme.Palette.mutedText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                HStack(alignment: .bottom) {
                    lines
                    if let updated = entry.updatedText {
                        Text(updated)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Theme.Palette.mutedText)
                            .frame(maxWidth: 80, alignment: .trailing)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .dimmed(entry.isStale)
        }
    }

    private func learningWord(_ verdict: LineVerdict, _ value: String) -> String {
        verdict.state.isLearning ? "Learning" : value
    }

    private var lines: some View {
        VStack(spacing: Theme.Spacing.s8) {
            WidgetLine(
                title: "Recovery", valueText: learningWord(entry.snapshot.lines.recovery, entry.recoveryWord), verdict: entry.snapshot.lines.recovery,
                color: entry.recoveryColor, layout: .inline, lineHeight: 6)
            WidgetLine(
                title: "Sleep", valueText: learningWord(entry.snapshot.lines.sleep, entry.sleepText), verdict: entry.snapshot.lines.sleep,
                color: Theme.Palette.sleep, layout: .inline, lineHeight: 6)
            WidgetLine(
                title: "Stress", valueText: entry.stress.ringText, verdict: entry.snapshot.lines.calm, color: Theme.Palette.stress, layout: .inline,
                lineHeight: 6)
        }
        .frame(maxWidth: .infinity)
    }
}

#if DEBUG
#Preview("Today", as: .systemMedium) {
    TodayWidget()
} timeline: {
    for entry in VeselEntry.previewStates() { entry }
}
#endif
