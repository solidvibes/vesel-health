import SwiftUI
import VeselCore

/// Recovery for one night: Polar's verdict over the 7 nights it sits in, the sentence and why, what went into it, and how it is worked out.
struct RecoveryDay: View {
    @State private var model: RecoveryModel
    @State private var nights: BodyModel
    @State private var selection: Date?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openPage) private var openPage

    init(environment: AppEnvironment, day: DayKey) {
        _model = State(
            initialValue: RecoveryModel(
                database: environment.database, clock: environment.clock, status: environment.status, units: environment.units, day: day))
        _nights = State(
            initialValue: BodyModel(database: environment.database, clock: environment.clock, units: environment.units, period: .week, endingOn: day))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s24) {
            PageHeader(
                text: HeaderText(
                    value: model.report?.status.map { "\($0.word.capitalizedFirst) · \($0.indicator) of 6" }
                        ?? (model.isLoaded ? (model.nightPending ? "Evaluating…" : "Not scored yet") : "—"),
                    line: PageDayLine.night(model.day, shown: model.report?.night, today: model.today, zone: model.zone)
                ), scrub: selection.flatMap { nights.scrubText(.recovery, at: $0) })
            NightsChart(kind: .recovery, day: model.day, model: nights, selection: $selection)
            LineRow(
                title: "Recovery", value: model.report?.status?.word.capitalizedFirst ?? "—",
                verdict: model.lines.recovery, color: Theme.Palette.recoveryLine(model.report?.status)
            )
            RecoveryView(model: model) { contributor, night in openPage(PageRoute(kind: PageKind(TrendKind(contributor)), day: night, period: .month)) }
            WhatHelpsCard(tips: model.helpTips, usualBedtime: model.usualBedtime)
        }
        .readProblem(model.readProblem || nights.readProblem)
        .task(id: ObserveKey(value: model.day, active: scenePhase == .active)) {
            guard scenePhase == .active else { return }
            await model.observe()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await nights.observe()
        }
        .task(id: ObserveKey(value: model.report?.night, active: scenePhase == .active)) {
            guard scenePhase == .active else { return }
            await model.observeUsualBedtime(before: model.report?.night)
        }
    }
}

#if DEBUG
#Preview("Day") { PreviewPage(kind: .recovery) }
#Preview("4 weeks") { PreviewPage(kind: .recovery, period: .month) }
#Preview("First day") { PreviewPage(kind: .recovery, scenario: .firstDay) }
#endif
