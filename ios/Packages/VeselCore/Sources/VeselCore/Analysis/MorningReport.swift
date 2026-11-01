import Foundation

/// The morning notification: last night in one line, once per night, once Polar's sleep and Nightly Recharge
/// for it are both stored.
public enum MorningReport {
    public static func due(_ facts: AlertFacts, now: Date) -> Alert? {
        guard facts.settings.isOn(.morningReport), !facts.wentOut(.morningReport, by: now),
            let night = facts.nights[facts.today], let minutes = night.asleepMinutes, let status = night.status
        else { return nil }
        let slept = DurationText.hoursMinutes(minutes: minutes)
        return Alert(
            kind: .morningReport, day: facts.today,
            title: "Last night",
            body: "Slept \(slept) · Recharge \(status.word)",
            explanation: Explanation(
                method: Alerts.method, version: Alerts.version,
                inputs: [
                    .init(name: "asleep", value: minutes, unit: "min"),
                    .init(name: "indicator", value: Double(status.indicator), unit: "of 6"),
                ],
                text: "Time asleep from Polar's sleep result (\(slept)) and Polar's Nightly Recharge word (\(status.word)), sent once the night is stored."
            )
        )
    }
}
