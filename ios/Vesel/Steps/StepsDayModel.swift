import Foundation
import Observation
import VeselCore
import VeselStorage

/// One day's steps for the Steps page: the day's total from the daily summary and the hours from the per-minute samples.
@MainActor
@Observable
final class StepsDayModel {
    private var loaded: (day: DayKey, snapshot: TodaySnapshot)?
    private var loadedHours: (day: DayKey, hours: HourlySteps)?
    private let reads = ReadProblem()
    private let database: AppDatabase
    private let clock: any VeselClock
    let day: DayKey
    /// The time `-VeselScrub` asks for, once.
    let takeLaunchScrub: () -> ScrubTime?

    init(database: AppDatabase, clock: any VeselClock, day: DayKey, takeLaunchScrub: @escaping () -> ScrubTime?) {
        self.database = database
        self.clock = clock
        self.day = day
        self.takeLaunchScrub = takeLaunchScrub
    }

    var today: DayKey { clock.today }
    var zone: TimeZone { clock.timeZone }
    var isToday: Bool { day == today }
    /// A read failed; the page shows its one "Couldn't show this" card.
    var readProblem: Bool { reads.isShown }

    /// False until both reads for the day have come back.
    var isReady: Bool { loaded?.day == day && loadedHours?.day == day }

    var steps: Int? { loaded.flatMap { $0.day == day ? $0.snapshot.steps : nil } }
    var readAt: Date? { loaded.flatMap { $0.day == day ? $0.snapshot.stepsReadAt : nil } }
    var hours: [HourlySteps.Hour] { loadedHours.flatMap { $0.day == day ? $0.hours.hours : nil } ?? [] }

    func observe() async {
        let shown = day
        await reads.observe {
            for try await value in database.observeToday(day: shown, today: today) { loaded = (shown, value) }
        }
    }

    func observeHours() async {
        let shown = day
        await reads.observe {
            for try await value in database.observeHourlySteps(day: shown) { loadedHours = (shown, value) }
        }
    }
}
