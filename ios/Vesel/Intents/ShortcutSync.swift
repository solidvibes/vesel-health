import Foundation
import VeselCore
import VeselStorage

/// The "Sync Vesel" Shortcut's read and what it says about last night.
struct ShortcutSync {
    let pipeline: SyncPipeline
    let database: AppDatabase
    let clock: any VeselClock

    @MainActor
    func run() async -> ShortcutResult {
        let time = BackgroundTime.begin("Sync Vesel Shortcut", database: database) { [pipeline] in pipeline.expire() }
        defer { time.end() }
        switch await pipeline.shortcut() {
        case nil, .unreachable?:
            return .notNearby
        default:
            let asleep = try? await database.computedMetric(MetricKind.sleepAsleep, day: clock.today)
            let status = (try? await database.computedMetric(MetricKind.recoveryStatus, day: clock.today)).flatMap(RecoveryStatus.init)
            guard let asleep, let status else { return .nightNotReady }
            return .lastNight(asleep: DurationText.hoursMinutes(minutes: asleep.value), recharge: status.word)
        }
    }
}

/// What the Shortcut says when it's done.
enum ShortcutResult: Equatable {
    case lastNight(asleep: String, recharge: String)
    /// Read, but Polar hasn't finished last night yet.
    case nightNotReady
    case notNearby
}
