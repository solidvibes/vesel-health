import AppIntents
import UIKit
import UserNotifications

/// Opens the app's environment before launch finishes, so the band and background refresh are set up even when
/// iOS launches Vesel in the background (Bluetooth state restoration, a band event, a refresh, the Shortcut).
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let startup = AppStartup()

    override init() {
        super.init()
        let startup = startup
        AppDependencyManager.shared.add(dependency: startup)
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        BackgroundScheduler.register(startup)
        startup.didFinishLaunching()
        return true
    }

    /// An alert that arrives while Vesel is open still shows as a banner.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions
    {
        [.banner, .list, .sound]
    }

    /// The morning report opens that night's Sleep page; every other Vesel notification opens Today.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let identifier = response.notification.request.identifier
        await startup.environment?.router.openNotification(identifier)
    }
}
