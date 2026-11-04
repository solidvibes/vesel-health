import Foundation
import Observation
import VeselCore
import VeselStorage

@MainActor
@Observable
final class SleepModel {
    /// The selected night's heart rate; nil while it is being read.
    private(set) var heartRates: [HeartRateSample]?
    private var resolved: (day: DayKey, night: DayKey?)?
    private(set) var usualBedtime: UsualBedtime?
    private var loadedReport: NightReport?
    private let reads = ReadProblem()
    private let database: AppDatabase
    private let clock: any VeselClock
    private let status: SyncStatusStore
    /// The day the model reads.
    let day: DayKey
    /// The time `-VeselScrub` asks for, once.
    let takeLaunchScrub: () -> ScrubTime?

    init(database: AppDatabase, clock: any VeselClock, status: SyncStatusStore, day: DayKey, takeLaunchScrub: @escaping () -> ScrubTime?) {
        self.database = database
        self.clock = clock
        self.status = status
        self.day = day
        self.takeLaunchScrub = takeLaunchScrub
    }

    var zone: TimeZone { clock.timeZone }
    var today: DayKey { clock.today }
    /// A read failed; the page shows its one "Couldn't show this" card.
    var readProblem: Bool { reads.isShown }

    /// Today, and last night isn't in yet but is on its way.
    var nightPending: Bool { day == today && status.nightOnItsWay(at: clock.now) }

    /// True once the night for the day has been looked up.
    var loaded: Bool { resolved?.day == day }

    /// The night shown for the day; nil while it is being looked up or when there is none.
    var shown: DayKey? { resolved.flatMap { $0.day == day ? $0.night : nil } }

    /// The shown night's report; nil while it is being read.
    var report: NightReport? { loadedReport.flatMap { $0.night == shown ? $0 : nil } }

    /// How the shown night's time asleep sits against your usual: the "Your normal" row.
    var sleepLine: LineVerdict? {
        report.map { InRange.sleep($0.metrics[Contributor.sleep.kind].flatMap(ContributorReading.init)) }
    }

    /// Time asleep against your normal, for "Your normal": the sleep line's own scale and ends. Nil while learning or with no sleep.
    var normalPicture: NightPicture? {
        guard let report, let reading = report.contributors.first(where: { $0.contributor == .sleep }), let line = sleepLine,
            let scale = line.scale, let low = line.normal.low, let high = line.normal.high, let mark = reading.mark
        else { return nil }
        let value = DurationText.hoursMinutes(minutes: reading.value)
        let ends = (low: DurationText.hoursMinutes(minutes: low), high: DurationText.hoursMinutes(minutes: high))
        let when = YoursText.night(report.night, today: today, zone: zone)
        return NightPicture(
            scale: scale, mark: mark, value: value, low: ends.low, high: ends.high,
            spoken: "\(when) \(value) asleep, \(mark.words). Your normal \(ends.low) to \(ends.high)."
        )
    }

    /// "What tends to help" for a short or long night; empty when sleep was in your normal.
    var helpTips: [String] {
        guard let sleepLine else { return [] }
        let lines = DayLines(recovery: DayLines.empty.recovery, sleep: sleepLine, calm: DayLines.empty.calm)
        return WhatHelps.tips(for: WhatHelps.sleepTopics(lines: lines), usualBedtime: usualBedtime?.text, busiestHours: nil)
    }

    /// Follows the usual bedtime before a night; the view restarts it when the shown night changes.
    func observeUsualBedtime(before night: DayKey?) async {
        usualBedtime = nil
        guard let night else { return }
        await reads.observe {
            for try await value in database.observeUsualBedtime(before: night, zone: zone) { usualBedtime = value }
        }
    }

    /// The view restarts it when the day changes.
    func observeShown() async {
        let shownDay = day
        await reads.observe {
            for try await night in database.observeShownNight(day: shownDay, today: today) {
                // Before last night is in, the database offers an older night for today; it never stands in for last night.
                resolved = (shownDay, night == shownDay ? night : nil)
            }
        }
    }

    /// Follows one night; the view restarts it when the shown night changes.
    func observeReport(_ night: DayKey?) async {
        guard let night else {
            loadedReport = nil
            return
        }
        await reads.observe {
            for try await value in database.observeNight(night) { loadedReport = value }
        }
    }

    /// Follows one night's heart rate; the view restarts it when the shown night changes.
    func observeHeartRates(_ night: DayKey?) async {
        heartRates = nil
        guard let night else { return }
        await reads.observe {
            for try await value in database.observeNightHeartRates(night) { heartRates = value }
        }
    }
}
