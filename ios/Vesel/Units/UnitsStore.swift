import Observation
import VeselCore
import VeselStorage

/// The owner's Metric / US choice, kept current from the `units` setting for every screen, pairing included.
@MainActor
@Observable
final class UnitsStore {
    private(set) var units: Units = .metric

    func observe(_ database: AppDatabase) async {
        do {
            for try await value in database.observeUnits() { units = value }
        } catch {
            // Keeps what it last read; it starts again when Vesel comes to the front.
        }
    }
}
