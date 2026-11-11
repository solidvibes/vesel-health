import Foundation
import Observation
import VeselCore
import VeselStorage
import VeselWearable

@MainActor
@Observable
final class TodayModel {
    private struct FailedOnPurpose: Error {}

    private var loaded: (day: DayKey, snapshot: TodaySnapshot)?
    private var loadedStepHours: (day: DayKey, hours: HourlySteps)?
    private var loadedWorkouts: (day: DayKey, workouts: [LabelledWorkout])?
    /// The newest reads, for spotting a stuck Loop.
    private var recentRuns: [SyncRun] = []
    /// The morning "Still in bed" was tapped; the card returns the next morning even if the app stayed open.
    private var dismissedOn: String?

    private static let dismissedKey = "goodMorningDismissedOn"
    /// Today's 5-minute heart rate, for the heart rate card's line.
    let heartRate: ReadingDayModel
    private let reads = ReadProblem()
    private let database: AppDatabase
    private let clock: any VeselClock
    private let status: SyncStatusStore
    private let unitsStore: UnitsStore
    private let defaults: UserDefaults
    private let liveReading: (Date) -> LiveHeartRate?
    private let sync: (SyncTrigger) async -> Void
    /// The next read of today fails once (`LaunchOptions.failsFirstRead`).
    private var failsNextRead: Bool

    init(
        database: AppDatabase,
        clock: any VeselClock,
        status: SyncStatusStore,
        units: UnitsStore,
        defaults: UserDefaults,
        liveReading: @escaping (Date) -> LiveHeartRate?,
        sync: @escaping (SyncTrigger) async -> Void,
        failsFirstRead: Bool
    ) {
        self.database = database
        self.clock = clock
        self.status = status
        unitsStore = units
        self.defaults = defaults
        self.liveReading = liveReading
        self.sync = sync
        failsNextRead = failsFirstRead
        heartRate = ReadingDayModel(database: database, clock: clock)
        dismissedOn = defaults.string(forKey: Self.dismissedKey)
    }

    var zone: TimeZone { clock.timeZone }
    /// A read failed; the screen shows its one "Couldn't show this" card.
    var readProblem: Bool { reads.isShown || heartRate.readProblem }
    var today: DayKey { clock.today }

    /// Today's snapshot; nil while it is being read.
    var snapshot: TodaySnapshot? { loaded.flatMap { $0.day == today ? $0.snapshot : nil } }

    /// A read changes Today only while `readingCard` follows it; any other read leaves Today as it is.
    func state(readingCard: ReadingCardGate) -> TodayState {
        let sync = status.sync
        return TodayState(
            sync: sync.isReading && !readingCard.followsRead ? .idle : sync,
            bandStillRecordingSleep: status.bandStillRecordingSleep,
            bandFinishingNight: status.bandFinishingNight(at: clock.now),
            sleepEndedAt: status.sleepEndedAt,
            dismissedGoodMorning: dismissedOn == today.description,
            imUp: status.imUp,
            latestNight: snapshot?.latest?.night,
            today: today,
            now: clock.now,
            timeZone: zone,
            earlierNights: snapshot?.earlierNights ?? 0,
            alertsToday: alerts.count
        )
    }

    /// Today's alerts that have gone out, newest first. One waiting for 07:00 isn't shown before then.
    var alerts: [AlertEvent] {
        let now = clock.now
        return snapshot?.alerts.filter { $0.firedAt <= now } ?? []
    }

    /// What the Calm row says: a level for a reading under 30 minutes old, else the day's high-stress time when it has one.
    func calmRingText(at date: Date) -> String {
        guard let snapshot else { return StressGlance.unknown.ringText }
        let glance = StressGlance(days: snapshot.stressDays, now: snapshot.stressNow, at: date)
        guard glance.ringText == StressGlance.unknown.ringText, let minutes = snapshot.lines.highMinutes, snapshot.lines.calm.scale != nil else {
            return glance.ringText
        }
        return StressDay.ringText(highMinutes: minutes)
    }

    /// Today's steps by hour, for the steps card's bars; empty while it is being read or with none.
    var stepHours: [HourlySteps.Hour] { loadedStepHours.flatMap { $0.day == today ? $0.hours.hours : nil } ?? [] }

    /// The workouts that started today, in time order; empty while they are being read or with none.
    var workouts: [LabelledWorkout] { loadedWorkouts.flatMap { $0.day == today ? $0.workouts : nil } ?? [] }

    /// Last night's resting heart rate; nil until last night is stored.
    var restingHeartRate: Double? {
        guard let latest = snapshot?.latest, latest.night == today else { return nil }
        return latest.contributors.first { $0.contributor == .restingHeartRate }?.value
    }

    func live(at date: Date) -> LiveHeartRate? { liveReading(date) }

    var headline: Headline? {
        guard let snapshot else { return nil }
        return Headline.make(
            lines: snapshot.lines,
            status: snapshot.latest?.status,
            contributors: snapshot.latest?.contributors ?? [],
            asleepMinutes: snapshot.latest?.value(MetricKind.sleepAsleep),
            units: unitsStore.units,
            yesterdayWorkout: snapshot.yesterdayWorkout
        )
    }

    /// Reads today from the database for as long as the screen is there; the database tells it when anything changes.
    /// The view restarts it when the day changes.
    func observe() async {
        let shown = today
        await reads.observe {
            if failsNextRead {
                failsNextRead = false
                throw FailedOnPurpose()
            }
            for try await value in database.observeToday(day: shown, today: shown) {
                loaded = (shown, value)
            }
        }
    }

    func observeHeartRate() async {
        await heartRate.observe(today)
    }

    func observeStepHours() async {
        let shown = today
        await reads.observe {
            for try await value in database.observeHourlySteps(day: shown) { loadedStepHours = (shown, value) }
        }
    }

    func observeWorkouts() async {
        let shown = today
        await reads.observe {
            for try await value in database.observeLabelledWorkouts(day: shown) { loadedWorkouts = (shown, value) }
        }
    }

    /// Since when the Loop has answered "busy" to every read (`LoopStuck`); nil when it isn't stuck.
    var loopStuckSince: Date? { LoopStuck.since(recentRuns, now: clock.now) }

    func observeRuns() async {
        await reads.observe {
            for try await log in database.observeSyncRuns(limit: 200) { recentRuns = log.runs }
        }
    }

    func tryAgain() async {
        await sync(.manual)
    }

    /// Kept until a read reaches the Loop, which ends the night there, then reads it.
    func imUp() async {
        status.tapImUp(at: clock.now)
        await sync(.imUp)
    }

    func stillInBed() {
        dismissedOn = today.description
        defaults.set(dismissedOn, forKey: Self.dismissedKey)
    }
}
