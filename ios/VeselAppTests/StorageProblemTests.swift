import Foundation
import Testing
import UIKit
import VeselCore
import VeselStorage
import VeselWearableTesting
@testable import Vesel

/// When the database won't open: which words the recovery screen shows, and that Vesel recovers by itself.
@MainActor
struct StorageProblemTests {
    struct Locked: Error {}

    /// Opens only once `isOpen` is set, like the database before the first unlock after a restart.
    @MainActor
    final class Opener {
        var isOpen = false
        var launches = 0

        func open() throws -> AppEnvironment {
            guard isOpen else { throw Locked() }
            let defaults = UserDefaults.throwaway()
            return AppEnvironment(
                database: try AppDatabase.inMemory(),
                band: try FakeWearableSource(scenario: .normal),
                clock: FixedClock(now: try Date("2026-10-25T13:00:00Z", strategy: .iso8601), timeZone: .gmt),
                launch: LaunchOptions(defaults: defaults),
                defaults: defaults
            )
        }

        func startup(_ notifications: NotificationCenter = NotificationCenter()) -> AppStartup {
            AppStartup(open: open, launch: { _ in self.launches += 1 }, notifications: notifications)
        }
    }

    @Test func eachErrorGetsItsWords() {
        #expect(StorageProblem(StorageError.newerSchema) == .olderApp)
        #expect(StorageProblem(StorageError.noAppGroup) == .setUp)
        #expect(StorageProblem(StorageError.notOpened) == .couldNotOpen)
        #expect(StorageProblem(Locked()) == .couldNotOpen)
    }

    @Test func tryAgainOpensOnceTheCauseIsGone() {
        let opener = Opener()
        let startup = opener.startup()
        startup.didFinishLaunching()
        #expect(startup.environment == nil)
        #expect(startup.problem == .couldNotOpen)
        #expect(opener.launches == 0)

        startup.retry()
        #expect(startup.problem == .couldNotOpen)

        opener.isOpen = true
        startup.retry()
        #expect(startup.environment != nil)
        #expect(startup.problem == nil)
        #expect(opener.launches == 1)

        startup.retry()
        #expect(opener.launches == 1)
    }

    /// iOS can launch Vesel in the background before the first unlock; nobody taps anything, so the unlock itself retries.
    @Test func theFirstUnlockOpensItInTheBackground() async {
        let notifications = NotificationCenter()
        let opener = Opener()
        let startup = opener.startup(notifications)
        startup.didFinishLaunching()
        #expect(startup.environment == nil)

        opener.isOpen = true
        notifications.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
        await waitUntil { startup.environment != nil }
        #expect(startup.environment != nil)
        #expect(opener.launches == 1)

        notifications.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(opener.launches == 1)
    }

    @Test func anOpenAtLaunchRunsTheLaunchWorkOnce() {
        let opener = Opener()
        opener.isOpen = true
        let startup = opener.startup()
        #expect(opener.launches == 0)
        startup.didFinishLaunching()
        startup.retry()
        #expect(opener.launches == 1)
    }
}
