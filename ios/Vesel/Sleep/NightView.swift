import SwiftUI
import VeselCore
import VeselStorage

/// The sleep part of Night under the chart: duration, times, stages, HRV, lowest heart rate, breathing.
struct NightView: View {
    let report: NightReport
    let sleepLine: LineVerdict?
    let zone: TimeZone
    let today: DayKey

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s16) {
            if let sleep = report.sleep {
                summary(sleep)
                stagesCard
            } else {
                EmptyState(
                    systemImage: "moon",
                    title: "No sleep for this night",
                    message: "Polar hasn't finished it yet; it fills in on the next read."
                )
            }
            details
        }
    }

    private func summary(_ sleep: SleepNight) -> some View {
        let asleep = report.metrics[MetricKind.sleepAsleep]
        return GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
                Text("Time asleep")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Palette.mutedText)
                Text(asleep.map { DurationText.hoursMinutes(minutes: $0.value) } ?? "—")
                    .font(Theme.Typography.display)
                    .foregroundStyle(Theme.Palette.text)
                Text("\(Formatters.time(sleep.start, zone: zone)) to \(Formatters.time(sleep.end, zone: zone))")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.mutedText)
                if let asleep {
                    MeaningRow(
                        term: .sleepTime, label: "Time asleep", value: DurationText.hoursMinutes(minutes: asleep.value),
                        yours: sleepYours(asleep), explanations: [("Time asleep", asleep.explanation)]
                    )
                }
                if let inBed = report.metrics[MetricKind.sleepInBed] {
                    ExplainedRow(label: "In bed", value: DurationText.hoursMinutes(minutes: inBed.value), explanation: inBed.explanation)
                }
                if let efficiency = report.metrics[MetricKind.sleepEfficiency] {
                    ExplainedRow(label: "Efficiency", value: "\(Formatters.whole(efficiency.value)) %", explanation: efficiency.explanation)
                }
                if let sleepLine, sleepLine.state != .none {
                    ExplainedRow(label: "Your normal", value: sleepLine.state.rowWord, explanation: sleepLine.explanation)
                }
            }
        }
    }

    private var stagesCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
                Text("Stages")
                    .font(Theme.Typography.heading)
                    .foregroundStyle(Theme.Palette.text)
                stageRows
            }
        }
    }

    private var stageRows: some View {
        VStack(spacing: 0) {
            ForEach([(SleepState.deep, Term.deepSleep), (.light, .lightSleep), (.rem, .remSleep), (.wake, .awake)], id: \.0) { state, term in
                if let metric = report.metrics[MetricKind.sleepStage(state)] {
                    MeaningRow(
                        term: term, label: SleepStagesChart.label(state),
                        value: DurationText.hoursMinutes(minutes: metric.value),
                        yours: stageYours(state, metric), explanations: [(SleepStagesChart.label(state), metric.explanation)]
                    )
                }
            }
        }
    }

    /// "Last night: 1 h 38 m, 23 % of your time asleep." (Awake: of your time in bed.)
    private func stageYours(_ state: SleepState, _ metric: ComputedMetric) -> String? {
        let whole = state == .wake ? report.metrics[MetricKind.sleepInBed] : report.metrics[MetricKind.sleepAsleep]
        guard let whole, whole.value > 0 else { return nil }
        let share = Formatters.whole(metric.value / whole.value * 100)
        return
            "\(YoursText.night(report.night, today: today, zone: zone)): \(DurationText.hoursMinutes(minutes: metric.value)), \(share) % of your time \(state == .wake ? "in bed" : "asleep")."
    }

    /// "Last night: 7 h 05 m asleep, within your normal (6 h 40 m–9 h 10 m)."
    private func sleepYours(_ asleep: ComputedMetric) -> String {
        let when = YoursText.night(report.night, today: today, zone: zone)
        if let reading = report.contributors.first(where: { $0.contributor == .sleep }) {
            return YoursText.contributor(reading, when: when)
        }
        return "\(when): \(DurationText.hoursMinutes(minutes: asleep.value)) asleep."
    }

    private func chartLink(_ kind: PageKind, value: String) -> some View {
        NavigationLink(value: PageRoute(kind: kind, day: report.night)) {
            HStack(spacing: Theme.Spacing.s12) {
                AdaptiveRow {
                    Text(kind.title)
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
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens \(kind.title)")
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var details: some View {
        let readings = Dictionary(uniqueKeysWithValues: report.contributors.map { ($0.contributor, $0) })
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s4) {
                Text("Overnight")
                    .font(Theme.Typography.heading)
                    .foregroundStyle(Theme.Palette.text)
                if let hrv = readings[.hrv] {
                    chartLink(.hrv, value: hrv.valueText())
                    Divider()
                }
                if let lowest = report.metrics[MetricKind.sleepLowestHeartRate] {
                    chartLink(.lowestHeartRate, value: "\(Formatters.whole(lowest.value)) bpm")
                    Divider()
                }
                if let breathing = readings[.breathing] {
                    chartLink(.breathing, value: breathing.valueText())
                }
            }
        }
    }
}

#if DEBUG
private struct PreviewNight: View {
    @State private var model: SleepModel

    init(environment: AppEnvironment) {
        _model = State(
            initialValue: SleepModel(
                database: environment.database, clock: environment.clock, status: environment.status, day: environment.clock.today, takeLaunchScrub: { nil }
            ))
    }

    var body: some View {
        ScrollView {
            if let report = model.report {
                NightView(report: report, sleepLine: model.sleepLine, zone: model.zone, today: model.today)
                    .padding(Theme.Spacing.edge)
            } else {
                ProgressView()
            }
        }
        .background { BlobBackground() }
        .task { await model.observeShown() }
        .task(id: model.shown) { await model.observeReport(model.shown) }
    }
}

#Preview("Normal") { PreviewHost { PreviewNight(environment: $0) } }
#endif
