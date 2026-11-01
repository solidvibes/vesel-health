import SwiftUI
import VeselCore

/// Steps for one day: the day's total and the hours it came in. No goal, no best hour.
struct StepsDay: View {
    @State private var model: StepsDayModel
    @State private var selection: Date?
    @Environment(\.scenePhase) private var scenePhase

    init(environment: AppEnvironment, day: DayKey) {
        _model = State(
            initialValue: StepsDayModel(database: environment.database, clock: environment.clock, day: day, takeLaunchScrub: environment.takeLaunchScrub))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s24) {
            PageHeader(text: header, scrub: scrub)
            if model.isReady {
                chart
            } else {
                SkeletonBlock(height: 240)
            }
        }
        .readProblem(model.readProblem)
        .task(id: ObserveKey(value: model.day, active: scenePhase == .active)) {
            guard scenePhase == .active else { return }
            await model.observe()
        }
        .task(id: ObserveKey(value: model.day, active: scenePhase == .active)) {
            guard scenePhase == .active else { return }
            await model.observeHours()
        }
    }

    private var scrub: HeaderText? {
        guard let selection else { return nil }
        let found = HourlyStepsChart.scrubText(at: selection, hours: model.hours, zone: model.zone)
        return HeaderText(value: found.steps.capitalizedFirst, line: "\(found.hour) · \(PageDayLine.day(model.day, today: model.today, zone: model.zone))")
    }

    private var header: HeaderText {
        let day = PageDayLine.day(model.day, today: model.today, zone: model.zone)
        guard model.isReady else { return HeaderText(value: "—", line: day) }
        guard let steps = model.steps else { return HeaderText(value: model.isToday ? "No steps yet today" : "No steps on this day", line: day) }
        let line = model.isToday ? "\(day) · so far" + (model.readAt.map { " · read \(Formatters.clock($0, zone: model.zone))" } ?? "") : day
        return HeaderText(value: "\(Formatters.steps(steps)) steps", line: line)
    }
}

private extension StepsDay {
    var chart: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
                if model.hours.isEmpty {
                    Text("No steps recorded by the hour on this day.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    let zone = model.zone
                    HourlyStepsChart(
                        hours: model.hours, day: model.day, zone: zone, takeLaunchScrub: model.takeLaunchScrub,
                        scrub: .holdThenDrag(slot: { HourlyStepsTime.hour(of: $0, zone: zone) }),
                        selection: $selection
                    )
                }
                Text("Steps per hour; hold a finger on the bars, then drag, to read one. Hours with no bar: no steps, or the band was off.")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#if DEBUG
#Preview("Day") { PreviewPage(kind: .steps) }
#Preview("4 weeks") { PreviewPage(kind: .steps, period: .month) }
#endif
