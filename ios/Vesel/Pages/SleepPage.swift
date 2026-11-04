import SwiftUI
import VeselCore

/// Sleep for one night: the stages with the overnight heart rate, the night's times, your normal, the stages and the overnight numbers.
struct SleepDay: View {
    @State private var model: SleepModel
    @State private var week: BodyModel
    @State private var selection: Date?
    @Environment(\.scenePhase) private var scenePhase

    init(environment: AppEnvironment, day: DayKey) {
        _model = State(
            initialValue: SleepModel(
                database: environment.database, clock: environment.clock, status: environment.status, day: day, takeLaunchScrub: environment.takeLaunchScrub))
        _week = State(
            initialValue: BodyModel(
                database: environment.database, clock: environment.clock, units: environment.units, period: .week, endingOn: day,
                kinds: [MetricKind.sleepInBed, MetricKind.sleepEfficiency, MetricKind.sleepLowestHeartRate]))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s24) {
            PageHeader(text: header, scrub: scrub)
            if let report = model.report, let sleep = report.sleep { chart(sleep) }
            content
            WhatHelpsCard(tips: model.helpTips, usualBedtime: model.usualBedtime)
        }
        .onChange(of: model.shown) { selection = nil }
        .readProblem(model.readProblem || week.readProblem)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await week.observe()
        }
        .task(id: ObserveKey(value: model.day, active: scenePhase == .active)) {
            guard scenePhase == .active else { return }
            await model.observeShown()
        }
        .task(id: ObserveKey(value: model.shown, active: scenePhase == .active)) {
            guard scenePhase == .active else { return }
            await model.observeReport(model.shown)
        }
        .task(id: ObserveKey(value: model.shown, active: scenePhase == .active)) {
            guard scenePhase == .active else { return }
            await model.observeHeartRates(model.shown)
        }
        .task(id: ObserveKey(value: model.shown, active: scenePhase == .active)) {
            guard scenePhase == .active else { return }
            await model.observeUsualBedtime(before: model.shown)
        }
    }
}

private extension SleepDay {
    var asleepText: String? { model.report?.value(MetricKind.sleepAsleep).map { DurationText.hoursMinutes(minutes: $0) } }

    var header: HeaderText {
        let line = PageDayLine.night(model.day, shown: model.shown, today: model.today, zone: model.zone)
        if let asleepText { return HeaderText(value: "\(asleepText) asleep", line: line) }
        guard model.loaded && model.shown == nil else { return HeaderText(value: "—", line: line) }
        return HeaderText(value: model.nightPending ? "Evaluating…" : "No sleep recorded", line: line)
    }

    var scrub: HeaderText? {
        guard let selection, let sleep = model.report?.sleep else { return nil }
        let found = SleepNightChart.scrubText(at: selection, sleep: sleep, heartRates: model.heartRates, zone: model.zone)
        let night = PageDayLine.night(model.day, shown: model.shown, today: model.today, zone: model.zone)
        return HeaderText(value: found.reading, line: "\(found.time) · \(night)")
    }

    func chart(_ sleep: SleepNight) -> some View {
        let zone = model.zone
        return GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
                SleepNightChart(
                    sleep: sleep, heartRates: model.heartRates, zone: zone, takeLaunchScrub: model.takeLaunchScrub,
                    scrub: .holdThenDrag(slot: { Int($0.timeIntervalSince1970) / 300 }),
                    selection: $selection
                )
                Text("Stages and heart rate through the night; hold a finger on the bars, then drag, to read one.")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func mark(_ kind: TrendKind, night: DayKey) -> NormalMark? {
        week.inRange(kind).first { $0.metric.day == night }?.mark
    }

    @ViewBuilder var content: some View {
        if let report = model.report {
            NightView(
                report: report, sleepLine: model.sleepLine, zone: model.zone, today: model.today, picture: model.normalPicture,
                efficiencyMark: mark(.efficiency, night: report.night), lowestHeartRateMark: mark(.lowestHeartRate, night: report.night)
            )
        } else if model.loaded && model.shown == nil && model.nightPending {
            EmptyState(systemImage: "moon", title: "Evaluating your night", message: "Your sleep shows here once your Loop has it ready.")
        } else if model.loaded && model.shown == nil {
            let isToday = model.day == model.today
            EmptyState(
                systemImage: "moon",
                title: isToday ? "No sleep recorded yet" : "No sleep recorded this night",
                message: isToday
                    ? "Wear your Loop tonight; the report appears after you wake up."
                    : "Your Loop has no sleep stored for it."
            )
        } else {
            SkeletonBlock(height: 200)
        }
    }
}

#if DEBUG
#Preview("Day") { PreviewPage(kind: .sleep) }
#Preview("4 weeks") { PreviewPage(kind: .sleep, period: .month) }
#endif
