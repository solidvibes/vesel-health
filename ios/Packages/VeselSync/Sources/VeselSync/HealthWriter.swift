import Foundation
import VeselCore
import VeselStorage

public enum HealthRunOutcome: Sendable, Equatable {
    case upToDate
    /// Cancelled (iOS ended the time): the rest waits for the next run.
    case stopped
    /// The phone is locked: the rest waits for the next run with it unlocked.
    case waitingForUnlock
    case failed
    /// The switch is off.
    case off
}

/// Copies what's pending into Apple Health, newest first, one unit at a time: save the new copies, then remove Vesel's own
/// older ones of the unit. Runs only from `SyncPipeline`, never beside a read, and only while protected data is available.
public struct HealthWriter: Sendable {
    private let database: AppDatabase
    private let store: any HealthStore
    private let clock: any VeselClock

    public init(database: AppDatabase, store: any HealthStore, clock: any VeselClock) {
        self.database = database
        self.store = store
        self.clock = clock
    }

    /// `askForNewKinds` shows Apple's sheet first when a kind was never asked about (only with Vesel on screen). Records
    /// `health.lastRun` unless the switch is off or the phone was locked from the start.
    public func run(askForNewKinds: Bool, isProtectedDataAvailable: @Sendable () async -> Bool) async -> HealthRunOutcome {
        guard (try? await database.healthStatus())?.isOn == true else { return .off }
        guard await isProtectedDataAvailable() else { return .waitingForUnlock }
        var access = await store.authorization()
        if askForNewKinds, access.values.contains(.notAsked) {
            try? await store.requestAuthorization()
            access = await store.authorization()
        }
        let allowed = Set(access.filter { $0.value == .allowed }.keys)
        var notAllowed = Set(access.filter { $0.value == .denied }.keys)

        var outcome = HealthRunOutcome.upToDate
        var left: [HealthUnit] = []
        do {
            left = try await database.pendingHealthUnits(kinds: allowed)
            while let unit = left.first {
                if Task.isCancelled {
                    outcome = .stopped
                    break
                }
                guard await isProtectedDataAvailable() else {
                    outcome = .waitingForUnlock
                    break
                }
                do {
                    try await write(unit, allowed: allowed)
                } catch HealthStoreError.notAllowed {
                    // Turned off in Health since the run began: it waits, shown as not allowed.
                    notAllowed.insert(unit.kind)
                }
                left.removeFirst()
            }
        } catch HealthStoreError.locked {
            outcome = .waitingForUnlock
        } catch {
            outcome = error is CancellationError || AppDatabase.isPaused(error) ? .stopped : .failed
        }

        let run = HealthRun(
            at: clock.now,
            outcome: outcome == .waitingForUnlock ? .waitingForUnlock : outcome == .failed ? .failed : .written,
            daysToGo: Set(left.map { $0.day?.description ?? $0.key }).count,
            notAllowed: HealthKind.allCases.filter(notAllowed.contains),
            wroteAny: (try? await database.hasHealthWrites()) ?? false
        )
        try? await database.saveHealthRun(run)
        return outcome
    }

    private func write(_ unit: HealthUnit, allowed: Set<HealthKind>) async throws {
        let read = try await database.healthBatch(unit, kinds: allowed, clock: clock)
        if let last = read.last, last.digest == read.batch.digest {
            try await database.markHealthWritten(unit, digest: last.digest, version: last.syncVersion, at: read.snapshot)
            return
        }
        guard !read.batch.items.isEmpty else {
            if let last = read.last {
                try await store.removeStale(unit: unit, kind: unit.kind, below: version(after: last))
                try await database.forgetHealthWrite(unit)
            } else {
                // Data with nothing to write (only hours without steps): remembered, so it isn't read again every run.
                try await database.markHealthWritten(unit, digest: read.batch.digest, version: 0, at: read.snapshot)
            }
            return
        }
        let version = version(after: read.last)
        try await store.save(read.batch.items, unit: unit, version: version)
        try await store.removeStale(unit: unit, kind: unit.kind, below: version)
        try await database.markHealthWritten(unit, digest: read.batch.digest, version: version, at: read.snapshot)
    }

    /// The clock's time in milliseconds, so versions keep rising across a reinstall; always above the last one.
    private func version(after last: HealthWritten?) -> Int64 {
        max(Int64((clock.now.timeIntervalSince1970 * 1000).rounded(.down)), (last?.syncVersion ?? 0) + 1)
    }
}
