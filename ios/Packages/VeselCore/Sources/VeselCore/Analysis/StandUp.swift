import Foundation

/// The opt-in stand-up reminder: the Loop's own inactivity alert, passed on to the iPhone as it came. Vesel never decides
/// inactivity itself and never reads or changes the band's setting for it.
public enum StandUp {
    /// A reminder that reaches the phone later than this is about a moment that has passed.
    public static let maximumAge: TimeInterval = 5 * 60

    public static func isTimely(_ alertedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(alertedAt) <= maximumAge
    }

    public static func alert(day: DayKey) -> Alert {
        Alert(
            kind: .standUp, day: day,
            title: "Time to move",
            body: "Your Loop says you've been still for a while.",
            explanation: Explanation(
                method: Alerts.method, version: Alerts.version,
                inputs: [],
                text: "Your Loop's own inactivity alert, passed on as it came."
            )
        )
    }
}
