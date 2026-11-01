import Foundation
import Observation
import UIKit
import VeselStorage

/// Opens the app's environment, or says why it couldn't. The database is readable only once the phone has been unlocked
/// after a restart, and iOS may launch Vesel in the background before that, so a failed open is tried again at the first
/// unlock and each time Vesel comes to the front. The launch work runs once, as soon as an open succeeds.
@MainActor
@Observable
final class AppStartup {
    private(set) var environment: AppEnvironment?
    private(set) var problem: StorageProblem?
    @ObservationIgnored private let open: @MainActor () throws -> AppEnvironment
    @ObservationIgnored private let launch: @MainActor (AppEnvironment) -> Void
    @ObservationIgnored private var launched = false
    @ObservationIgnored private var unlockObserver: (any NSObjectProtocol)?

    init(
        open: @escaping @MainActor () throws -> AppEnvironment = AppEnvironment.live,
        launch: @escaping @MainActor (AppEnvironment) -> Void = { $0.didFinishLaunching() },
        notifications: NotificationCenter = .default
    ) {
        self.open = open
        self.launch = launch
        attempt()
        unlockObserver = notifications.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main) {
            [weak self] _ in
            // Delivered on the main queue (`queue: .main`); the compiler can't see that.
            MainActor.assumeIsolated { self?.retry() }
        }
    }

    /// From `didFinishLaunching`.
    func didFinishLaunching() {
        launched = true
        if let environment { launch(environment) }
    }

    /// Tries to open again if it failed before. Does nothing once open.
    func retry() {
        guard environment == nil else { return }
        attempt()
        if launched, let environment { launch(environment) }
    }

    private func attempt() {
        do {
            environment = try open()
            problem = nil
        } catch {
            problem = StorageProblem(error)
        }
    }
}

/// Why the database couldn't be opened, in the words the recovery screen uses. Never the error itself.
enum StorageProblem: Equatable {
    /// A newer Vesel migrated the database.
    case olderApp
    /// The build has no App Group to keep the database in.
    case setUp
    /// Anything else, most often a phone that hasn't been unlocked since it restarted.
    case couldNotOpen

    init(_ error: any Error) {
        switch error as? StorageError {
        case .newerSchema?: self = .olderApp
        case .noAppGroup?: self = .setUp
        default: self = .couldNotOpen
        }
    }
}
