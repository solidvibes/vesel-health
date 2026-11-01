import SwiftUI
import VeselCore
import VeselStorage
import WidgetKit

struct RecoveryRingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.vesel.ios.recovery", provider: Provider()) { entry in
            RecoveryRingEntryView(entry: entry)
                .widgetURL(URL(string: "vesel://recovery"))
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("Recovery")
        .description("Polar's Nightly Recharge verdict for last night.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct RecoveryRingEntryView: View {
    let entry: VeselEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular: RecoveryRingCircularView(entry: entry).privacySensitive()
        default: RecoveryRingSmallView(entry: entry)
        }
    }
}

struct RecoveryRingSmallView: View {
    let entry: VeselEntry

    @ViewBuilder var body: some View {
        if entry.content == .noData {
            NoDataFace()
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
                WidgetLine(
                    title: "Recovery", valueText: entry.recoveryWord, verdict: entry.snapshot.lines.recovery,
                    color: entry.recoveryColor, layout: .card
                )
                .dimmed(entry.isStale)
                if let caption = entry.updatedText ?? entry.learningText {
                    Text(caption)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.Palette.mutedText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

/// Polar's word in the middle of the arc; when the snapshot is old the time shows under it.
struct RecoveryRingCircularView: View {
    let entry: VeselEntry

    var body: some View {
        let verdict = entry.snapshot.lines.recovery
        RangeArc(scale: verdict.scale, outside: verdict.state.isOutside, color: .primary, lineWidth: 6) {
            VStack(spacing: 0) {
                Text(entry.recoveryWord)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if entry.isStale, let synced = entry.snapshot.syncedAt {
                    Text(synced.formatted(date: .omitted, time: .shortened))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(3)
        .dimmed(entry.isStale)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recovery")
        .accessibilityValue(
            entry.content == .noData ? "No data yet" : verdict.state.spokenValue(entry.recoveryWord) + (entry.updatedText.map { ", \($0)" } ?? ""))
    }
}

#if DEBUG
#Preview("Recovery", as: .systemSmall) {
    RecoveryRingWidget()
} timeline: {
    for entry in VeselEntry.previewStates() { entry }
}

#Preview("Recovery ring", as: .accessoryCircular) {
    RecoveryRingWidget()
} timeline: {
    for entry in VeselEntry.previewStates() { entry }
}
#endif
