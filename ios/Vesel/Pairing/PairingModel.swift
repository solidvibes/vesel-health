import Foundation
import Observation
import VeselCore
import VeselStorage
import VeselWearable

enum PairingStep: String {
    case before, looking, aboutYou
}

@MainActor
@Observable
final class PairingModel {
    enum Looking: Equatable {
        case searching, notFound, refused
    }

    var step: PairingStep
    var looking: Looking = .searching
    var draft = ProfileDraft()
    private(set) var finishing = false
    private(set) var setupFailed = false

    private let bandSync: BandSync
    private let database: AppDatabase
    private let clock: any VeselClock
    private let unitsStore: UnitsStore
    private let didPair: () -> Void
    private var paired: PairedBand?
    private var search: Task<Void, Never>?

    init(bandSync: BandSync, database: AppDatabase, clock: any VeselClock, units: UnitsStore, launchStep: PairingStep, didPair: @escaping () -> Void) {
        self.bandSync = bandSync
        self.database = database
        self.clock = clock
        unitsStore = units
        self.didPair = didPair
        step = launchStep
        if step == .looking { startLooking() }
    }

    func startLooking() {
        step = .looking
        looking = .searching
        search = Task {
            do {
                paired = try await bandSync.pair()
                step = .aboutYou
            } catch PairingError.refused {
                looking = .refused
            } catch is CancellationError {
                return
            } catch {
                looking = .notFound
            }
        }
    }

    func cancel() {
        search?.cancel()
        Task { [bandSync] in await bandSync.cancelPairing() }
        step = .before
    }

    var currentYear: Int { Calendar.current.component(.year, from: clock.now) }

    var units: Units { unitsStore.units }

    var canFinish: Bool {
        !finishing && draft.profile(currentYear: currentYear) != nil
    }

    func finish() {
        guard !finishing, let profile = draft.profile(currentYear: currentYear) else { return }
        finishing = true
        setupFailed = false
        Task {
            defer { finishing = false }
            var profile = profile
            // Pairing again after a reset: step 3 doesn't ask for waist or the outside VO2max, so keep the stored ones.
            if let stored = try? await database.profile() {
                profile.waistCm = stored.waistCm
                profile.measuredVO2max = stored.measuredVO2max
            }
            do {
                try await bandSync.firstTimeUse(profile)
                guard let band = paired else { throw PairingError.setupFailed }
                try await database.save(profile)
                try await database.save(BandInfo(deviceId: band.deviceId, name: band.name, pairedAt: clock.now))
                didPair()
            } catch {
                setupFailed = true
            }
        }
    }
}
