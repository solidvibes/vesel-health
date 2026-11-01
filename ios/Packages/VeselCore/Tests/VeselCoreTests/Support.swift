import Foundation
import VeselCore

let berlin = TimeZone(identifier: "Europe/Berlin")!

func at(_ iso: String) -> Date {
    try! Date(iso, strategy: .iso8601)
}

func day(_ string: String) -> DayKey {
    DayKey(string)!
}

/// The night of 2026-10-26 in Berlin (UTC+1): 22:30 to 06:30, eight hours in bed.
///
/// | From (s) | State | Seconds |
/// |---|---|---|
/// | 0 | light | 1800 |
/// | 1800 | deep | 3600 |
/// | 5400 | light | 1800 |
/// | 7200 | rem | 1800 |
/// | 9000 | wake | 600 |
/// | 9600 | light | 4800 |
/// | 14400 | deep | 3600 |
/// | 18000 | rem | 3600 |
/// | 21600 | light | 6600 |
/// | 28200 | wake | 600 |
///
/// Light 15 000 s (250 min), deep 7 200 s (120 min), rem 5 400 s (90 min), awake 1 200 s (20 min).
func sampleNight() -> SleepNight {
    let phases: [(Int, SleepState)] = [
        (0, .light), (1800, .deep), (5400, .light), (7200, .rem), (9000, .wake),
        (9600, .light), (14400, .deep), (18000, .rem), (21600, .light), (28200, .wake),
    ]
    return SleepNight(
        night: day("2026-10-26"),
        start: at("2026-10-25T21:30:00Z"),
        end: at("2026-10-26T05:30:00Z"),
        goalMinutes: 480,
        phases: phases.map { SleepPhase(secondsFromStart: $0.0, state: $0.1) }
    )
}

/// Seven earlier nights of one measure, 2026-10-19 to 2026-10-25.
func history(_ contributor: Contributor, _ values: [Double], endingOn last: String = "2026-10-25") -> [DayKey: [Contributor: Double]] {
    var result: [DayKey: [Contributor: Double]] = [:]
    for (offset, value) in values.reversed().enumerated() {
        result[day(last).adding(days: -offset)] = [contributor: value]
    }
    return result
}

/// Contributor readings for `night`, as the screens get them back from the database.
func readings(night: String = "2026-10-26", _ values: [Contributor: Double], history: [DayKey: [Contributor: Double]]) -> [ContributorReading] {
    var merged = ContributorValues()
    merged.values = values
    return
        RecoveryContributors
        .metrics(night: day(night), values: merged, history: history, computedAt: at("2026-10-26T06:00:00Z"))
        .compactMap(ContributorReading.init)
}

/// Beats from `intervals` in milliseconds. `flagged` are positions with the blocker set; `noSkin` positions without skin contact.
func beats(_ intervals: [Int], start: Date, flagged: Set<Int> = [], noSkin: Set<Int> = []) -> [PPISample] {
    var elapsed = 0
    return intervals.enumerated().map { index, interval in
        elapsed += interval
        return PPISample(
            time: start.addingTimeInterval(Double(elapsed) / 1000), intervalMs: interval, errorMs: 5,
            blocker: flagged.contains(index), skinContact: !noSkin.contains(index)
        )
    }
}

/// `count` beats alternating 1000 and 1040 ms: every successive difference is 40 ms, so RMSSD is exactly 40 ms.
func alternating(_ count: Int) -> [Int] {
    (0..<count).map { $0 % 2 == 0 ? 1000 : 1040 }
}

/// A session starting at `start` (Berlin is UTC+1 on 2026-10-26) with those beats.
func session(_ intervals: [Int], at start: String = "2026-10-26T09:00:00Z", flagged: Set<Int> = [], noSkin: Set<Int> = []) -> PPISession {
    let begin = at(start)
    return PPISession(start: begin, trigger: .automatic, utcOffsetSeconds: 3600, samples: beats(intervals, start: begin, flagged: flagged, noSkin: noSkin))
}
