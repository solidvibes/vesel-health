#if VESEL_FAKE_BAND
import Foundation

/// Named sets of synthetic band data for the Simulator, picked with the launch argument `-VeselScenario <name>`.
public enum FakeScenario: String, Sendable, CaseIterable {
    /// A paired band with 30 days of data.
    case normal
    /// A band in factory state waiting to be paired; it carries the same 30 days.
    case pairing
    /// Like `normal`, but the band's storage is 84 % full.
    case bandFull
    /// Like `normal`, but the band's battery is at 18 %.
    case lowBattery
    /// Only the first four nights: Vesel is still learning your normal.
    case firstDay
    /// Only the very first night: every chart has a single point.
    case firstNight
    /// Like `normal`, but every read takes 3 seconds, so the "reading" state stays on screen.
    case slowRead
    /// The Loop can't be reached.
    case unreachable
    /// Everything but sleep and Nightly Recharge.
    case noSleep
    /// The band still records sleep: Today asks "I'm up".
    case stillAsleep
    /// Like `normal`, but beat-to-beat data only for the last three days: stress is still learning your normal.
    /// (A stressful day is in `normal` itself: its last day has a stressed afternoon.)
    case stressLearning
    /// Like `normal`, but the last two nights' Nightly Recharge is poor and very poor with a low HRV: a low-recovery alert.
    case offDay
    /// Like `normal`, but the last night's sleep runs 150 minutes longer, well above your usual, and its Nightly Recharge is good, so the long night is what Today says.
    case longNight

    public init(defaults: UserDefaults = .standard) {
        self.init(named: defaults.string(forKey: "VeselScenario"))
    }

    /// An unknown or missing name means `normal`.
    public init(named name: String?) {
        self = name.flatMap(FakeScenario.init(rawValue:)) ?? .normal
    }

    var fixtures: String { "normal" }
}

/// A problem the fake band acts out, picked with `-VeselFakeFailure <name>` (Simulator screenshots, tests).
public enum FakeFailure: String, Sendable, CaseIterable {
    case notFound, refused, setupFailed, wristFailed, unreachable

    public init?(defaults: UserDefaults) {
        guard let failure = defaults.string(forKey: "VeselFakeFailure").flatMap(FakeFailure.init(rawValue:)) else { return nil }
        self = failure
    }
}
#endif
