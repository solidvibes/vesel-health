import Foundation
import Observation
import VeselCore
import VeselWearable

/// What Today needs to know about the band right now. Written by `SyncPipeline`, read by the screens.
/// Only what the band said, what the sync is doing and a waiting "I'm up"; never health values.
@MainActor
@Observable
final class SyncStatusStore {
    private(set) var sync: SyncStatus = .idle
    /// The band said sleep is still recording (or couldn't say) at the last read that reached it.
    private(set) var bandStillRecordingSleep = false
    /// When the band was first seen to have stopped recording sleep after recording it, or Vesel ended the night; Polar then
    /// needs up to ~90 minutes. Kept across launches, so reopening the app still knows last night is on its way.
    private(set) var sleepEndedAt: Date?
    /// "I'm up" was tapped and the Loop hasn't got it yet. Kept across launches.
    private(set) var imUp: ImUpRequest?

    private let defaults: UserDefaults
    private static let sleepEndedKey = "sleepEndedAt"
    private static let imUpKey = "imUpRequest"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        sleepEndedAt = defaults.object(forKey: Self.sleepEndedKey) as? Date
        imUp = defaults.data(forKey: Self.imUpKey).flatMap { try? JSONDecoder().decode(ImUpRequest.self, from: $0) }
    }

    func set(_ status: SyncStatus) {
        sync = status
    }

    /// A step of the running read; ignored once the read is over. Waiting for the Loop shows as its own status until it answers.
    func report(_ step: SyncStep) {
        switch (sync, step) {
        case (.reading, .waitingForLoop): sync = .waitingForLoop
        case (.waitingForLoop, .loopFound): sync = .reading(SyncProgress().applying(.loopFound))
        case (.reading(let progress), _): sync = .reading(progress.applying(step))
        default: break
        }
    }

    /// Today's stress is worked out from what was just read.
    func stressWorkedOut() {
        if case .reading(var progress) = sync {
            progress.stressToday = true
            sync = .reading(progress)
        }
    }

    /// The band stopped recording sleep under 2 hours ago: Polar may still be finishing the night.
    func bandFinishingNight(at now: Date) -> Bool {
        sleepEndedAt.map { now.timeIntervalSince($0) < 2 * 3600 } ?? false
    }

    /// Last night is on its way: the band still records it, Polar is still finishing it, it is being read, or "I'm up" waits
    /// for the Loop.
    func nightOnItsWay(at now: Date) -> Bool {
        bandStillRecordingSleep || bandFinishingNight(at: now) || sync.isReading || imUp?.isWaiting(at: now) == true
    }

    /// Nil (the Loop wasn't reached, or nothing read since launch) keeps what the band last said.
    func set(sleep: SleepRecordingStatus?, at now: Date) {
        guard let sleep else { return }
        if bandStillRecordingSleep, sleep == .stopped { stampSleepEnded(now) }
        bandStillRecordingSleep = sleep != .stopped
    }

    /// Vesel ended the night on the band: Polar's ~90 minutes start now, whatever was known before.
    func nightEnded(at now: Date) {
        stampSleepEnded(now)
        bandStillRecordingSleep = false
    }

    func tapImUp(at now: Date) {
        save(ImUpRequest(tappedAt: now))
    }

    /// A read tried to deliver the waiting "I'm up" and didn't find the Loop.
    func imUpMissedLoop() {
        guard var request = imUp else { return }
        request.missedLoop = true
        save(request)
    }

    func clearImUp() {
        save(nil)
    }

    private func save(_ request: ImUpRequest?) {
        imUp = request
        defaults.set(request.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.imUpKey)
    }

    private func stampSleepEnded(_ now: Date) {
        sleepEndedAt = now
        defaults.set(now, forKey: Self.sleepEndedKey)
    }
}
