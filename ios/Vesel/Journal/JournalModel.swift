import Foundation
import Observation
import VeselCore
import VeselStorage

/// The picked day's night and day, read for Journal's cards.
@MainActor
@Observable
final class JournalModel {
    private var loaded: (day: DayKey, snapshot: TodaySnapshot)?
    private var loadedStress: StressReport?
    private var loadedSteps: (day: DayKey, hours: HourlySteps)?
    private var loadedWorkouts: (day: DayKey, workouts: [LabelledWorkout])?
    let heartRate: ReadingDayModel
    private let reads = ReadProblem()
    private let database: AppDatabase
    private let clock: any VeselClock
    private let status: SyncStatusStore
    private let unitsStore: UnitsStore
    private let days: DaySelection

    init(database: AppDatabase, clock: any VeselClock, status: SyncStatusStore, units: UnitsStore, days: DaySelection) {
        self.database = database
        self.clock = clock
        self.status = status
        unitsStore = units
        self.days = days
        heartRate = ReadingDayModel(database: database, clock: clock)
    }

    var day: DayKey { days.day }
    var today: DayKey { clock.today }
    var zone: TimeZone { clock.timeZone }
    var isToday: Bool { day == today }
    /// A read failed; the screen shows its one "Couldn't show this" card.
    var readProblem: Bool { reads.isShown || heartRate.readProblem }

    /// The snapshot for the picked day; nil while it is being read.
    var snapshot: TodaySnapshot? { loaded.flatMap { $0.day == day ? $0.snapshot : nil } }

    /// The picked day's own night. Before last night is in, the database offers an older night for today; it never stands in.
    var night: NightReport? { snapshot?.latest.flatMap { $0.night == day ? $0 : nil } }

    /// Today, and last night isn't in yet but is on its way.
    var nightPending: Bool { isToday && night == nil && status.nightOnItsWay(at: clock.now) }

    /// "Monday night, October 26": the night the cards are about.
    var nightLine: String { Formatters.nightEvening(day, zone: zone) }

    var sleepValue: String {
        if nightPending { return "Evaluating…" }
        guard let asleep = night?.value(MetricKind.sleepAsleep) else {
            return isToday ? "No sleep recorded yet" : "No sleep recorded this night"
        }
        return DurationText.hoursMinutes(minutes: asleep)
    }

    /// "Good · 5 of 6"; "Polar hasn't scored this night yet" without a verdict.
    var recoveryValue: String {
        if nightPending { return "Evaluating…" }
        guard let status = night?.status else { return "Polar hasn't scored this night yet" }
        return "\(status.word.capitalizedFirst) · \(status.indicator) of 6"
    }

    /// Today: "8 m so far · Calm now"; a past day: "45 m".
    func calmValue(at date: Date) -> String {
        guard let snapshot, let minutes = snapshot.lines.highMinutes else { return "—" }
        let high = DurationText.hoursMinutes(minutes: minutes)
        guard isToday else { return high }
        let now = snapshot.stressNow.flatMap { $0.isRecent(at: date) ? "\($0.band.word.capitalizedFirst) now" : nil }
        return ["\(high) so far", now].compactMap { $0 }.joined(separator: " · ")
    }

    /// The picked day's hourly stress bars; empty while it is being read or with no readings.
    var stressHours: [StressHour] {
        guard let report = loadedStress, report.day == day else { return [] }
        return StressModel.hours(report)
    }

    /// The picked day's hourly step bars; empty while it is being read or with no steps.
    var stepHours: [HourlySteps.Hour] { loadedSteps.flatMap { $0.day == day ? $0.hours.hours : nil } ?? [] }

    /// The workouts that started on the picked day, in time order; empty while they are being read or with none.
    var workouts: [LabelledWorkout] { loadedWorkouts.flatMap { $0.day == day ? $0.workouts : nil } ?? [] }

    /// The day's lowest to highest; nil with no readings.
    var heartRateRange: DailyHeartRate.Range? {
        heartRate.loaded(day)?.metric.flatMap(DailyHeartRate.Range.init)
    }

    var heartRateIsReady: Bool { heartRate.loaded(day) != nil }

    /// What recovery leaned on: the contributor furthest from your usual, else HRV.
    var mainContributor: ContributorReading? {
        let contributors = night?.contributors ?? []
        return RecoverySentence.driver(contributors) ?? contributors.first { $0.contributor == .hrv }
    }

    var units: Units { unitsStore.units }

    /// The view restarts it when the day changes.
    func observe() async {
        let shown = day
        await reads.observe {
            for try await value in database.observeToday(day: shown, today: today) {
                loaded = (shown, value)
            }
        }
    }

    func observeStress() async {
        await reads.observe {
            for try await value in database.observeStress(day: day) { loadedStress = value }
        }
    }

    func observeSteps() async {
        let shown = day
        await reads.observe {
            for try await value in database.observeHourlySteps(day: shown) { loadedSteps = (shown, value) }
        }
    }

    func observeWorkouts() async {
        let shown = day
        await reads.observe {
            for try await value in database.observeLabelledWorkouts(day: shown) { loadedWorkouts = (shown, value) }
        }
    }

    func observeHeartRate() async {
        await heartRate.observe(day)
    }
}
