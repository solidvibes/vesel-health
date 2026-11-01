import Observation
import VeselStorage

/// Whether a screen's reads failed, for its one "Couldn't show this" card. A read that was cancelled, or that ended because
/// Vesel paused the database in the background, is not a problem: the screen starts its reads again when Vesel comes back.
@MainActor
@Observable
final class ReadProblem {
    /// The observations whose last run failed, by the function that runs them.
    private var failed: Set<String> = []

    var isShown: Bool { !failed.isEmpty }

    /// Runs one observation for as long as it lasts. Starting clears its own earlier failure, never a sibling's; a failure sets it.
    func observe(_ read: () async throws -> Void, observation: String = #function) async {
        failed.remove(observation)
        do {
            try await read()
        } catch {
            if Self.counts(error) { failed.insert(observation) }
        }
    }

    static func counts(_ error: any Error) -> Bool {
        !(error is CancellationError) && !AppDatabase.isPaused(error)
    }
}
