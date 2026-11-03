import SwiftUI
import VeselCore
import VeselStorage

/// Calm for one day: how long you were highly stressed, the hours with a finger to read them, how stressed you are now (today), and how it is worked out.
struct CalmDay: View {
    @State private var model: StressModel
    @State private var selection: Date?
    @Environment(\.setPageMeaning) private var setMeaning
    @Environment(\.scenePhase) private var scenePhase

    init(environment: AppEnvironment, day: DayKey) {
        _model = State(
            initialValue: StressModel(database: environment.database, clock: environment.clock, day: day, takeLaunchScrub: environment.takeLaunchScrub))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s24) {
            PageHeader(text: header, scrub: scrub)
            if let report = model.shown {
                if !report.isLearning { chart(report) }
            } else {
                SkeletonBlock(height: 220)
            }
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                LineRow(title: "Stress", value: model.rowText(at: model.now), verdict: model.shownCalm, color: Theme.Palette.stress)
            }
            if let report = model.shown {
                if report.isLearning {
                    CalmLearning(model: model, report: report)
                } else {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s16) {
                        CalmHeadline(model: model)
                        CalmWorkedOut(model: model, report: report)
                        WhatHelpsCard(tips: model.helpTips, usualBedtime: nil)
                    }
                }
            } else {
                SkeletonBlock(height: 40, width: 240)
            }
        }
        .onChange(of: model.shown, initial: true) {
            setMeaning(
                PageMeaning(
                    yours: model.shown.flatMap { $0.isLearning ? nil : yours },
                    explanations: model.shown?.readings.map { [("Stress", $0.explanation)] } ?? []
                ))
        }
        .readProblem(model.readProblem)
        .task(id: ObserveKey(value: model.day, active: scenePhase == .active)) {
            guard scenePhase == .active else { return }
            await model.observe()
        }
        .task(id: ObserveKey(value: model.day, active: scenePhase == .active)) {
            guard scenePhase == .active else { return }
            await model.observeCalm()
        }
        .task(id: ObserveKey(value: model.day, active: scenePhase == .active)) {
            guard scenePhase == .active else { return }
            await model.observeBusiestSpan()
        }
        .task(id: ObserveKey(value: model.day, active: scenePhase == .active)) {
            guard scenePhase == .active else { return }
            await model.observeWorkouts()
        }
    }

    private var dayLine: String { PageDayLine.day(model.day, today: model.today, zone: model.zone) }

    /// The time in high stress ("45 m high stress"; today "so far"), or the learning wording.
    private var header: HeaderText {
        guard let report = model.shown else { return HeaderText(value: "—", line: dayLine) }
        if report.isLearning { return HeaderText(value: model.learningText ?? "Learning your normal", line: dayLine) }
        guard let minutes = report.highMinutes?.value else {
            return HeaderText(value: model.hours.isEmpty ? "No stress readings" : "—", line: dayLine)
        }
        let value = Int(minutes.rounded()) == 0 ? "No high stress" : "\(DurationText.hoursMinutes(minutes: minutes)) high stress"
        return HeaderText(value: value, line: model.isToday ? "\(dayLine) · so far" : dayLine)
    }

    private var scrub: HeaderText? {
        guard let selection else { return nil }
        let found = HourlyStressChart.scrubText(at: selection, hours: model.hours, emptyHours: model.emptyHours, zone: model.zone)
        let workout =
            HourlyStressChart.workout(
                in: HourlyStepsTime.hour(of: selection, zone: model.zone), day: model.day, zone: model.zone, workouts: model.workouts
            ).map { " · \($0.capitalizedFirst)" } ?? ""
        return HeaderText(value: found.level.capitalizedFirst + workout, line: "\(found.hour) · \(dayLine)")
    }

    /// "Today: peak 72 (high), 14:00–15:00."; a past day "On this day: …".
    private var yours: String? {
        guard let top = model.hours.max(by: { $0.level < $1.level }), let first = model.hours.first(where: { $0.level == top.level }) else { return nil }
        return "\(model.dayWord.capitalizedFirst): peak \(Formatters.whole(top.level)) (\(first.band.word)), \(Formatters.hourRange(first.hour))."
    }

    private func chart(_ report: StressReport) -> some View {
        let zone = model.zone
        return GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
                if model.hours.isEmpty {
                    Text(
                        model.isToday
                            ? "No readings yet today. The Loop records them in short sessions; bars appear for the hours it did." : "No readings on this day."
                    )
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    HourlyStressChart(
                        hours: model.hours, emptyHours: model.emptyHours, day: report.day, zone: zone, workouts: model.workouts,
                        takeLaunchScrub: model.takeLaunchScrub,
                        scrub: .holdThenDrag(slot: { HourlyStepsTime.hour(of: $0, zone: zone) }),
                        selection: $selection
                    )
                    Text(
                        "Based on \(model.readings) readings \(model.dayWord). Each bar is the hour's middle reading. Hold a finger on the bars, then drag, to read one, or to see why an hour has none."
                    )
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                    if !model.workouts.isEmpty {
                        Text(
                            "Purple: "
                                + model.workouts.map {
                                    "\($0.word) \(Formatters.clock($0.range.lowerBound, zone: zone))–\(Formatters.clock($0.range.upperBound, zone: zone))"
                                }.joined(separator: ", ") + ". Readings inside a workout aren't counted."
                        )
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Palette.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// Until there are enough days of readings: the learning wording and why.
struct CalmLearning: View {
    let model: StressModel
    let report: StressReport

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s16) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
                Text(model.learningText ?? "Learning your normal")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Stress compares each reading with what is calm for you. That needs \(StressThresholds.minimumDays) days of readings first.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            CalmWorkedOut(model: model, report: report)
        }
    }
}

/// "Calm now." or "45 m of high stress.", and the peak hour.
struct CalmHeadline: View {
    let model: StressModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: model.isToday ? 30 : 3600)) { _ in
            VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
                if let headline = model.headline(at: model.now) {
                    Text(headline)
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let peak = model.peak {
                    Text(peak)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.mutedText)
                }
            }
        }
    }
}

struct CalmWorkedOut: View {
    let model: StressModel
    let report: StressReport

    var body: some View {
        if let readings = report.readings {
            GlassCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
                    Text("How it's worked out")
                        .font(Theme.Typography.heading)
                        .foregroundStyle(Theme.Palette.text)
                    ExplanationView(explanation: readings.explanation)
                    if let calm = model.shownCalm, calm.state != .none {
                        Divider()
                        ExplainedRow(label: "Your normal", value: calm.state.rowWord, explanation: calm.explanation)
                    }
                }
            }
        }
    }
}

#if DEBUG
#Preview("Day") { PreviewPage(kind: .stress) }
#Preview("4 weeks") { PreviewPage(kind: .stress, period: .month) }
#endif
