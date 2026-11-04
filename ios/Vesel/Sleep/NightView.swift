import SwiftUI
import VeselCore
import VeselStorage

/// The sleep part of the page under the chart: the night's times, in bed and efficiency, your normal for time asleep, the stages, and the
/// overnight signals. Each row that has a page opens it; the marks come from the screen's week of nights (nil while they are read).
struct NightView: View {
    let report: NightReport
    let sleepLine: LineVerdict?
    let zone: TimeZone
    let today: DayKey
    var picture: NightPicture?
    var efficiencyMark: NormalMark?
    var lowestHeartRateMark: NormalMark?
    @Environment(\.setPageMeaning) private var setMeaning

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s16) {
            if let sleep = report.sleep {
                nightCard(sleep)
                normalCard
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
        .onChange(of: report.night, initial: true) {
            setMeaning(
                PageMeaning(
                    yours: report.metrics[MetricKind.sleepAsleep].map(sleepYours),
                    explanations: report.metrics[MetricKind.sleepAsleep].map { [("Time asleep", $0.explanation)] } ?? []
                ))
        }
    }

    private func nightCard(_ sleep: SleepNight) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s4) {
                Text("The night")
                    .font(Theme.Typography.heading)
                    .foregroundStyle(Theme.Palette.text)
                SignalLinkRow(
                    kind: .bedtime, value: "\(Formatters.clock(sleep.start, zone: zone)) to \(Formatters.clock(sleep.end, zone: zone))", day: report.night)
                if let inBed = report.metrics[MetricKind.sleepInBed] {
                    Divider()
                    SignalLinkRow(kind: .inBed, value: DurationText.hoursMinutes(minutes: inBed.value), day: report.night)
                }
                if let efficiency = report.metrics[MetricKind.sleepEfficiency] {
                    Divider()
                    SignalLinkRow(kind: .efficiency, value: "\(Formatters.whole(efficiency.value)) %", mark: efficiencyMark, day: report.night)
                }
            }
        }
    }

    /// Time asleep against your normal, as a picture; while learning, the learning words. Its numbers are folded.
    @ViewBuilder private var normalCard: some View {
        let asleep = report.metrics[MetricKind.sleepAsleep]
        let reading = report.contributors.first { $0.contributor == .sleep }
        if let asleep, let sleepLine, picture != nil || reading.map({ $0.range == nil }) == true {
            GlassCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
                    Text("Your normal")
                        .font(Theme.Typography.heading)
                        .foregroundStyle(Theme.Palette.text)
                    if let picture {
                        NormalPicture(
                            scale: picture.scale, mark: picture.mark, color: Theme.Palette.sleep, value: picture.value, low: picture.low,
                            high: picture.high, spoken: picture.spoken
                        )
                    } else if let reading {
                        Text(LearningText.nights(reading.nights))
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HowItsWorkedOutRow(
                        framed: false, title: "Show the numbers", explanations: [asleep.explanation, sleepLine.explanation],
                        labels: ["Time asleep", "Your normal"]
                    )
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

    @ViewBuilder private var details: some View {
        let readings = Dictionary(uniqueKeysWithValues: report.contributors.map { ($0.contributor, $0) })
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s4) {
                Text("Overnight")
                    .font(Theme.Typography.heading)
                    .foregroundStyle(Theme.Palette.text)
                if let hrv = readings[.hrv] {
                    SignalLinkRow(kind: .hrv, value: hrv.valueText(), mark: hrv.mark, day: report.night)
                    Divider()
                }
                if let lowest = report.metrics[MetricKind.sleepLowestHeartRate] {
                    SignalLinkRow(
                        kind: .lowestHeartRate, value: "\(Formatters.whole(lowest.value)) bpm", mark: lowestHeartRateMark, day: report.night)
                    Divider()
                }
                if let breathing = readings[.breathing] {
                    SignalLinkRow(kind: .breathing, value: breathing.valueText(), mark: breathing.mark, day: report.night)
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
