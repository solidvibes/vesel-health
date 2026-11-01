import SwiftUI
import VeselCore
import VeselStorage
import WidgetKit

struct SleepLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.vesel.ios.sleep", provider: Provider()) { entry in
            SleepLockView(entry: entry)
                .privacySensitive()
                .widgetURL(URL(string: "vesel://sleep"))
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Recovery and sleep")
        .description("Last night's recovery and sleep against your normal.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct SleepLockView: View {
    let entry: VeselEntry

    var body: some View {
        if entry.content == .noData {
            VStack(alignment: .leading, spacing: 2) {
                Label("Vesel", systemImage: "moon")
                    .font(.headline)
                Text("No data yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                WidgetLine(title: "Recovery", valueText: entry.recoveryWord, verdict: entry.snapshot.lines.recovery, color: .primary, lineHeight: 6)
                WidgetLine(title: "Sleep", valueText: entry.updatedText ?? entry.sleepText, verdict: entry.snapshot.lines.sleep, color: .primary, lineHeight: 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dimmed(entry.isStale)
        }
    }
}

#if DEBUG
#Preview("Recovery and sleep", as: .accessoryRectangular) {
    SleepLockWidget()
} timeline: {
    for entry in VeselEntry.previewStates() { entry }
}
#endif
