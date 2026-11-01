import SwiftUI
import VeselCore
import VeselStorage
import VeselWearable

/// Heart rate for one day: the day's 5-minute line with sleep shaded, lowest, highest and average. Today opens with the live reading.
struct HeartRateDay: View {
    let day: DayKey
    private let environment: AppEnvironment
    @State private var model: ReadingDayModel
    @State private var selection: Date?
    @Environment(\.setPageMeaning) private var setMeaning
    @Environment(\.scenePhase) private var scenePhase

    init(environment: AppEnvironment, day: DayKey) {
        self.environment = environment
        self.day = day
        _model = State(initialValue: ReadingDayModel(database: environment.database, clock: environment.clock, takeLaunchScrub: environment.takeLaunchScrub))
    }

    private var today: DayKey { environment.clock.today }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s24) {
            PageHeader(text: header, scrub: scrub)
            if model.isReady(day) {
                HeartRateDayContent(day: day, model: model, selection: $selection) {
                    if day == today { now }
                }
            } else {
                SkeletonBlock(height: 280)
            }
        }
        .onChange(of: model.isReady(day), initial: true) {
            setMeaning(
                PageMeaning(
                    yours: model.isReady(day) ? HeartRateDayContent<EmptyView>.yours(day: day, model: model, today: today) : nil,
                    explanations: HeartRateDayContent<EmptyView>.explanations(day: day, model: model)
                ))
        }
        .readProblem(model.readProblem)
        .task(id: ObserveKey(value: day, active: scenePhase == .active)) {
            guard scenePhase == .active else { return }
            await model.observe(day)
        }
        .task(id: ObserveKey(value: day, active: scenePhase == .active)) {
            guard scenePhase == .active else { return }
            await model.observeLatest(day)
        }
    }

    private var scrub: HeaderText? {
        guard let selection, let points = model.loaded(day)?.points else { return nil }
        let found = ReadingDayChart.scrubText(at: selection, points: points, zone: model.zone, unit: "bpm", format: { Formatters.whole($0) })
        return HeaderText(value: found.reading.capitalizedFirst, line: "\(found.time) · \(PageDayLine.day(day, today: today, zone: model.zone))")
    }

    /// The day's lowest to highest, as Journal's card says it.
    private var header: HeaderText {
        let line = PageDayLine.day(day, today: today, zone: model.zone)
        guard model.isReady(day) else { return HeaderText(value: "—", line: line) }
        guard let metric = model.loaded(day)?.metric, let range = DailyHeartRate.Range(metric) else {
            return HeaderText(value: "No heart rate recorded", line: line)
        }
        return HeaderText(value: "\(Formatters.whole(range.lowest))–\(Formatters.whole(range.highest)) bpm", line: line)
    }

    /// The live heart rate while the stream runs, else the latest stored reading.
    private var now: some View {
        GlassCard {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let live = environment.liveHeartRate.reading(at: context.date)
                AdaptiveRow(alignment: .firstTextBaseline) {
                    Label("Now", systemImage: "heart")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.text)
                } trailing: {
                    LiveHeartRateText(live: live, latest: model.latest, zone: model.zone)
                        .multilineTextAlignment(.trailing)
                }
                .frame(minHeight: Theme.Size.row)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// The live bpm with its pulsing dot while the stream runs, "Check the fit" without skin contact, else the latest stored reading and its time.
struct LiveHeartRateText: View {
    let live: LiveHeartRate?
    let latest: HeartRateSample?
    let zone: TimeZone
    var empty = "—"

    var body: some View {
        if let live, live.skinContact == false {
            Text("Check the fit")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.mutedText)
        } else if let live {
            HStack(spacing: Theme.Spacing.s8) {
                Text("\(live.bpm) bpm")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.text)
                    .contentTransition(.numericText())
                LiveDot()
            }
        } else if let latest {
            Text("\(latest.bpm) bpm at \(Formatters.time(latest.time, zone: zone))")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.mutedText)
        } else {
            Text(empty)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.mutedText)
        }
    }

    /// What VoiceOver says for it.
    static func spoken(live: LiveHeartRate?, latest: HeartRateSample?, zone: TimeZone, empty: String) -> String {
        if let live, live.skinContact == false { return "Check the fit" }
        if let live { return "\(live.bpm) bpm, live" }
        if let latest { return "\(latest.bpm) bpm at \(Formatters.time(latest.time, zone: zone))" }
        return empty
    }
}

/// One day's heart rate: the 5-minute line, `now` under it (today's live reading), lowest, highest and average, and how it is worked out.
struct HeartRateDayContent<Now: View>: View {
    let day: DayKey
    let model: ReadingDayModel
    @Binding var selection: Date?
    @ViewBuilder let now: Now

    var body: some View {
        if let periods = model.loaded(day), let metric = periods.metric, let range = DailyHeartRate.Range(metric) {
            let zone = model.zone
            GlassCard {
                ReadingDayChart(
                    day: day, points: periods.points, spans: model.spans(day) ?? [], zone: zone, unit: "bpm", color: Theme.Palette.recovery,
                    format: { Formatters.whole($0) },
                    spokenLabel:
                        "Heart rate on \(Formatters.day(day, zone: zone)), lowest \(Formatters.whole(range.lowest)) at \(Formatters.clock(range.lowestAt, zone: zone)), highest \(Formatters.whole(range.highest)) at \(Formatters.clock(range.highestAt, zone: zone))",
                    takeLaunchScrub: model.takeLaunchScrub,
                    scrub: .holdThenDrag(slot: { Int($0.timeIntervalSince1970) / Int(FiveMinuteMean.seconds) }),
                    selection: $selection
                )
                .id(day)
            }
            now
            GlassCard {
                VStack(spacing: 0) {
                    ListRow(label: "Lowest", value: "\(Formatters.whole(range.lowest)) bpm · \(Formatters.clock(range.lowestAt, zone: zone))")
                    ListRow(label: "Highest", value: "\(Formatters.whole(range.highest)) bpm · \(Formatters.clock(range.highestAt, zone: zone))")
                    ListRow(label: "Day's average", value: "\(Formatters.whole(metric.value)) bpm")
                }
            }
            HowItsWorkedOutRow(explanations: [metric.explanation])
        } else {
            now
            Text("No heart rate recorded on this day.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.mutedText)
        }
    }

    /// "Today: lowest 52, highest 118, average 71 bpm."
    static func yours(day: DayKey, model: ReadingDayModel, today: DayKey) -> String? {
        guard let metric = model.loaded(day)?.metric, let range = DailyHeartRate.Range(metric) else { return nil }
        let when = YoursText.day(day, today: today, zone: model.zone)
        return "\(when): lowest \(Formatters.whole(range.lowest)), highest \(Formatters.whole(range.highest)), average \(Formatters.whole(metric.value)) bpm."
    }

    static func explanations(day: DayKey, model: ReadingDayModel) -> [(label: String, explanation: Explanation)] {
        model.loaded(day)?.metric.map { [("Heart rate", $0.explanation)] } ?? []
    }
}

#if DEBUG
#Preview("Day") { PreviewPage(kind: .heartRate) }
#Preview("4 weeks") { PreviewPage(kind: .heartRate, period: .month) }
#endif
