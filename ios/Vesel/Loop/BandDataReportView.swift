#if DEBUG
import SwiftUI
import VeselCore
import VeselStorage

/// Debug only: how densely the band records 24/7 data, per hour for the last 3 days, and the link to the Loop for the
/// last 2 days. Counts, times and words only, no values, so the owner can share them for tuning.
struct BandDataReportView: View {
    let environment: AppEnvironment
    @State private var hours: [BandDataHour] = []
    @State private var links: [BandLink] = []
    @State private var streaming = false

    var body: some View {
        ZStack {
            BlobBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.s24) {
                    GlassCard {
                        VStack(spacing: 0) {
                            ListRow(label: "Live heart-rate stream", value: streaming ? "On" : "Off")
                        }
                    }
                    Text(
                        "PPI: beat-to-beat sessions. Beats/PPI: intervals per session. Flagged: intervals the band marked unreliable or recorded without skin contact. HR: 24/7 heart-rate samples."
                    )
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Palette.mutedText)
                    if hours.isEmpty {
                        EmptyState(systemImage: "tablecells", title: "No 24/7 data yet", message: "Counts show here after a sync.")
                    }
                    ForEach(days, id: \.self) { day in
                        daySection(day, hours.filter { $0.day == day })
                    }
                    connection
                }
                .padding(.horizontal, Theme.Spacing.edge)
                .padding(.top, Theme.Spacing.s16)
                .padding(.bottom, Theme.Spacing.s32)
            }
            TopFade()
        }
        .navigationTitle("Band data report")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
            while !Task.isCancelled {
                streaming = await environment.pipeline.isStreaming
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var days: [DayKey] {
        Array(Set(hours.map(\.day))).sorted(by: >)
    }

    private func load() async {
        let today = environment.clock.today
        let zone = environment.clock.timeZone
        hours = (try? await environment.pipeline.bandDataReport(from: today.adding(days: -2), through: today)) ?? []
        links = (try? await environment.database.bandLinks(since: today.adding(days: -1).start(in: zone))) ?? []
    }

    private var connection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
            Text("Connection")
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Palette.mutedText)
            GlassCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
                    if links.isEmpty {
                        Text("No changes in the last 2 days.")
                            .font(Theme.Typography.small)
                            .foregroundStyle(Theme.Palette.mutedText)
                    }
                    ForEach(Array(links.reversed().enumerated()), id: \.offset) { _, link in
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s8) {
                            Text(link.at.formatted(.dateTime.day().month(.abbreviated).hour().minute().second()))
                                .foregroundStyle(Theme.Palette.mutedText)
                            Text([Self.word(link.event), link.reason].compactMap { $0 }.joined(separator: " · "))
                                .foregroundStyle(Theme.Palette.text)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .font(Theme.Typography.small.monospacedDigit())
                    }
                }
            }
        }
    }

    private static func word(_ event: BandLink.Event) -> String {
        switch event {
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .disconnected: "Disconnected"
        case .bluetoothOff: "Bluetooth off"
        case .bluetoothOn: "Bluetooth on"
        }
    }

    private func daySection(_ day: DayKey, _ hours: [BandDataHour]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
            Text(day.description)
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Palette.mutedText)
            GlassCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
                    row("Hour", "PPI", "Beats/PPI", "Flagged", "HR")
                        .foregroundStyle(Theme.Palette.mutedText)
                    Divider()
                    ForEach(hours, id: \.hour) { hour in
                        row(
                            String(format: "%02d", hour.hour),
                            "\(hour.ppiSessions)",
                            hour.ppiSessions > 0 ? "\(hour.ppiIntervals / hour.ppiSessions)" : "–",
                            hour.ppiIntervals > 0
                                ? (Double(hour.ppiFlagged) / Double(hour.ppiIntervals)).formatted(.percent.precision(.fractionLength(0)))
                                : "–",
                            "\(hour.hrSamples)"
                        )
                        .foregroundStyle(Theme.Palette.text)
                    }
                }
            }
        }
    }

    private func row(_ columns: String...) -> some View {
        HStack(spacing: Theme.Spacing.s4) {
            ForEach(Array(columns.enumerated()), id: \.offset) { index, text in
                Text(text)
                    .frame(maxWidth: .infinity, alignment: index == 0 ? .leading : .trailing)
            }
        }
        .font(Theme.Typography.small.monospacedDigit())
    }
}
#endif
