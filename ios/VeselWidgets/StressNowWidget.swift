import SwiftUI
import VeselCore
import VeselStorage
import WidgetKit

struct StressNowWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.vesel.ios.stress", provider: Provider()) { entry in
            StressNowView(entry: entry)
                .widgetURL(URL(string: "vesel://stress"))
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("Stress now")
        .description("How stressed your latest reading says you are.")
        .supportedFamilies([.systemSmall])
    }
}

struct StressNowView: View {
    let entry: VeselEntry

    var body: some View {
        if entry.content == .noData {
            NoDataFace()
        } else {
            let stress = entry.stress
            VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
                WidgetLine(
                    title: "Stress now", valueText: stress.ringText, verdict: entry.snapshot.lines.calm,
                    color: Theme.Palette.stress, layout: .card
                )
                .dimmed(entry.isStale)
                if let caption = entry.updatedText ?? (entry.snapshot.lines.calm.scale == nil ? stress.rowText : nil) {
                    Text(caption)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.Palette.mutedText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

#if DEBUG
#Preview("Stress now", as: .systemSmall) {
    StressNowWidget()
} timeline: {
    for entry in VeselEntry.previewStates() { entry }
}
#endif
