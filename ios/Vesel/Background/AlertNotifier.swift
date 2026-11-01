import Foundation
import UserNotifications
import VeselCore
import VeselStorage

/// After each sync: works out which alerts are due, records them and hands them to iOS as local notifications.
/// A notification says only what its `Alert` says, and is never logged. Found in quiet hours, it waits for 07:00
/// and is dropped again if a later sync finds it no longer true.
struct AlertNotifier {
    let database: AppDatabase
    let clock: any VeselClock

    func update() async {
        let now = clock.now
        let today = clock.today
        guard let facts = try? await database.alertFacts(today: today, timeZone: clock.timeZone) else { return }
        let due = Alerts.due(facts, now: now) + [MorningReport.due(facts, now: now)].compactMap { $0 }
        let center = UNUserNotificationCenter.current()

        var sent = Set<AlertKind>()
        for alert in due {
            let firesAt: Date
            switch AlertTiming.delivery(at: now, in: clock.timeZone) {
            case .skip: continue
            case .now: firesAt = now
            case .at(let morning): firesAt = morning
            }
            guard (try? await database.save(AlertEvent(alert, firedAt: firesAt))) != nil else { continue }
            sent.insert(alert.kind)
            try? await center.add(request(alert, firesAt: firesAt > now ? firesAt : nil))
        }
        for (kind, firesAt) in facts.firedToday where firesAt > now && !sent.contains(kind) {
            try? await database.deleteAlertEvent(kind, day: today)
            center.removePendingNotificationRequests(withIdentifiers: [AlertIdentifier.make(kind, today)])
        }
    }

    /// A stand-up reminder, now: silent (not a warning), never stored in `alert_event`, under one fixed id so the
    /// newest replaces the last.
    func standUp(_ alert: Alert) async {
        let request = request(alert, firesAt: nil)
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "alert.\(AlertKind.standUp.rawValue)", content: request.content, trigger: nil)
        )
    }

    private func request(_ alert: Alert, firesAt: Date?) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = alert.kind.isWarning ? .default : nil
        content.threadIdentifier = alert.kind.rawValue
        let trigger = firesAt.map { date -> UNCalendarNotificationTrigger in
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = clock.timeZone
            return UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date),
                repeats: false
            )
        }
        return UNNotificationRequest(identifier: AlertIdentifier.make(alert.kind, alert.day), content: content, trigger: trigger)
    }

    /// iOS asks the owner once; after that this does nothing.
    static func askPermissionOnce() async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }
}
