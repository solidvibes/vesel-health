import Foundation
import Observation
import VeselCore
import VeselStorage

@MainActor
@Observable
final class RecoveryModel {
    private var loaded: (day: DayKey, report: NightReport?, lines: DayLines)?
    private(set) var usualBedtime: UsualBedtime?
    private let reads = ReadProblem()
    private let database: AppDatabase
    private let clock: any VeselClock
    private let status: SyncStatusStore
    private let unitsStore: UnitsStore
    /// The day the model reads.
    let day: DayKey

    init(database: AppDatabase, clock: any VeselClock, status: SyncStatusStore, units: UnitsStore, day: DayKey) {
        self.database = database
        self.clock = clock
        self.status = status
        unitsStore = units
        self.day = day
    }

    var zone: TimeZone { clock.timeZone }
    var today: DayKey { clock.today }
    var units: Units { unitsStore.units }
    /// A read failed; the page shows its one "Couldn't show this" card.
    var readProblem: Bool { reads.isShown }

    /// The night shown for the day; nil while it is being read or when there is none.
    var report: NightReport? { shown?.report }
    var lines: DayLines { shown?.lines ?? .empty }
    var isLoaded: Bool { shown != nil }
    /// Today, and last night isn't in yet but is on its way.
    var nightPending: Bool { day == today && status.nightOnItsWay(at: clock.now) }

    private var shown: (report: NightReport?, lines: DayLines)? {
        loaded.flatMap { $0.day == day ? ($0.report, $0.lines) : nil }
    }

    var quietLine: String? {
        report.flatMap { RecoverySentence.quietLine(status: $0.status, contributors: $0.contributors) }
    }

    /// "What tends to help" for what was off this night; empty on a good night.
    var helpTips: [String] {
        guard let report else { return [] }
        let topics = WhatHelps.recoveryTopics(lines: lines, contributors: report.contributors)
        return WhatHelps.tips(for: topics, usualBedtime: usualBedtime?.text, busiestHours: nil)
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
    func observe() async {
        let shown = day
        await reads.observe {
            for try await snapshot in database.observeToday(day: shown, today: clock.today) {
                // An older night never stands in for last night.
                let night = snapshot.latest?.night == shown ? snapshot.latest : nil
                loaded = (shown, night, night == nil ? .empty : snapshot.lines)
            }
        }
    }
}
