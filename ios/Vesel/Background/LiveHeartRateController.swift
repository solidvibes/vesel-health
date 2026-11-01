import Foundation
import Observation
import VeselWearable

/// Live heart rate while Vesel is on screen. Display only: never stored, never logged.
@MainActor
@Observable
final class LiveHeartRateController {
    private(set) var current: LiveHeartRate?
    private(set) var isOn = false
    private let bandSync: BandSync
    /// Start and stop requests run in order, so a quick leave-and-return ends with the stream on.
    private var last: Task<Void, Never>?

    init(bandSync: BandSync) {
        self.bandSync = bandSync
        let values = bandSync.liveHeartRate
        Task { [weak self] in
            for await value in values {
                guard let self else { return }
                if isOn { current = value }
            }
        }
    }

    /// The live reading while the stream runs. One older than 5 seconds means it is off (paused for a sync, band out of reach).
    func reading(at date: Date) -> LiveHeartRate? {
        current.flatMap { date.timeIntervalSince($0.time) < 5 ? $0 : nil }
    }

    func sceneBecameActive() {
        guard !isOn else { return }
        isOn = true
        enqueue { await $0.startLiveHeartRate() }
    }

    func sceneLeftScreen() {
        guard isOn else { return }
        isOn = false
        current = nil
        enqueue { await $0.stopLiveHeartRate() }
    }

    private func enqueue(_ work: @escaping @Sendable (BandSync) async -> Void) {
        let previous = last
        let bandSync = bandSync
        last = Task {
            await previous?.value
            await work(bandSync)
        }
    }
}
