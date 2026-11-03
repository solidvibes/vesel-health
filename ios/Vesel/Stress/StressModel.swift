import Foundation
import Observation
import VeselCore
import VeselStorage

/// One bar of the hourly chart.
struct StressHour: Identifiable, Equatable {
    let hour: Int
    let level: Double
    let readings: Int
    var band: StressLevel { StressLevel(level: level) }
    var id: Int { hour }
}

@MainActor
@Observable
final class StressModel {
    private(set) var report: StressReport?
    private var busiestSpan: StressSpan?
    private var loadedCalm: (day: DayKey, line: LineVerdict)?
    /// The day's workouts, for the purple blocks behind the bars.
    private(set) var workouts: [WorkoutSpan] = []
    private let reads = ReadProblem()
    private let database: AppDatabase
    private let clock: any VeselClock
    /// The day the model reads.
    let day: DayKey
    /// The time `-VeselScrub` asks for, once.
    let takeLaunchScrub: () -> ScrubTime?

    init(database: AppDatabase, clock: any VeselClock, day: DayKey, takeLaunchScrub: @escaping () -> ScrubTime?) {
        self.database = database
        self.clock = clock
        self.day = day
        self.takeLaunchScrub = takeLaunchScrub
    }

    var isToday: Bool { day == today }

    /// The report for the day on screen; nil while it is being read.
    var shown: StressReport? { report.flatMap { $0.day == day ? $0 : nil } }

    /// "today" for today, "on this day" for a past day.
    var dayWord: String { isToday ? "today" : "on this day" }

    var zone: TimeZone { clock.timeZone }
    var today: DayKey { clock.today }
    var now: Date { clock.now }
    /// A read failed; the page shows its one "Couldn't show this" card.
    var readProblem: Bool { reads.isShown }

    /// The calm line's verdict for the day on screen; nil while it is being read.
    var shownCalm: LineVerdict? { loadedCalm.flatMap { $0.day == day ? $0.line : nil } }

    func observeWorkouts() async {
        await reads.observe {
            for try await value in database.observeWorkoutSpans(day: day, zone: zone) { workouts = value }
        }
    }

    func observe() async {
        await reads.observe {
            for try await value in database.observeStress(day: day) {
                report = value
            }
        }
    }

    /// "What tends to help" when calm was above your normal; the busiest-hours tip only for today.
    var helpTips: [String] {
        guard let calm = shownCalm else { return [] }
        let lines = DayLines(recovery: DayLines.empty.recovery, sleep: DayLines.empty.sleep, calm: calm)
        let busiest = isToday ? busiestSpan.map { "\(Formatters.clock($0.start, zone: zone))–\(Formatters.clock($0.end, zone: zone))" } : nil
        return WhatHelps.tips(for: WhatHelps.calmTopics(lines: lines), usualBedtime: nil, busiestHours: busiest)
    }

    func observeBusiestSpan() async {
        busiestSpan = nil
        await reads.observe {
            for try await value in database.observeBusiestSpan(day: day) { busiestSpan = value }
        }
    }

    func observeCalm() async {
        let shown = day
        await reads.observe {
            for try await value in database.observeDayLines(from: shown, through: shown) {
                loadedCalm = (shown, value[shown]?.calm ?? DayLines.empty.calm)
            }
        }
    }

    var hours: [StressHour] { Self.hours(report) }

    /// One bar per hour that had readings.
    static func hours(_ report: StressReport?) -> [StressHour] {
        (report?.hourly ?? []).compactMap { metric in
            metric.hour.map { StressHour(hour: $0, level: metric.value, readings: Int(metric.explanation.inputs.first { $0.name == "readings" }?.value ?? 0)) }
        }
    }

    var emptyHours: [StressEmptyHour] { report?.emptyHours ?? [] }

    var readings: Int { Int(report?.readings?.value ?? 0) }

    /// Today: "Calm now.", "Moderately stressed now." or "No recent reading."; a past day: "45 m of high stress.", or nil.
    func headline(at date: Date) -> String? {
        guard isToday else { return StressDay.sentence(highMinutes: report?.highMinutes?.value) }
        guard let now = report?.now, now.isRecent(at: date) else { return StressNow.noRecentReading }
        return now.sentence
    }

    /// What the Calm row says: today a level for a reading under 30 minutes old; a past day, its high-stress time.
    func rowText(at date: Date) -> String {
        guard let report = shown else { return "—" }
        return isToday
            ? StressGlance(days: report.baselineDays, now: report.now, at: date).ringText
            : StressDay.ringText(highMinutes: report.highMinutes?.value)
    }

    /// "Peak 14:00–15:00, high": the hour with the highest level, the first one when several tie.
    var peak: String? { Self.peak(hours) }

    static func peak(_ hours: [StressHour]) -> String? {
        guard let top = hours.max(by: { $0.level < $1.level }),
            let first = hours.first(where: { $0.level == top.level })
        else { return nil }
        return "Peak \(Formatters.hourRange(first.hour)), \(first.band.word)"
    }

    var learningText: String? {
        report.flatMap { $0.isLearning ? LearningText.days($0.baselineDays) : nil }
    }
}
