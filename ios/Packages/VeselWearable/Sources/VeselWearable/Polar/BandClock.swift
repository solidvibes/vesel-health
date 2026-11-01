import Foundation
import VeselCore

/// The band shows wall time in the UTC offset Vesel last set at a sync; it knows nothing of clock changes. So on the
/// day the clocks go back it keeps summer time until a sync sets it back, which shows as its times stepping back.
/// Every other time is read in the zone's offset at that moment; a time the clocks skipped is still in the old offset.
struct BandClock {
    let day: DayKey
    let zone: TimeZone

    /// The UTC offset of each of the day's wall times (seconds from the band's midnight), given in the band's order.
    func offsets(_ times: [Int]) -> [Int] {
        let before = zone.secondsFromGMT(for: day.start(in: zone))
        let after = zone.secondsFromGMT(for: day.adding(days: 1).start(in: zone))
        if after < before, let step = times.indices.dropFirst().first(where: { times[$0] < times[$0 - 1] }) {
            return times.indices.map { $0 < step ? before : offsets(at: times[$0]).last! }
        }
        return times.map { offsets(at: $0).first! }
    }

    /// The offsets in which this wall time exists, earlier moment first: two in the repeated hour, one otherwise.
    private func offsets(at time: Int) -> [Int] {
        let wall = day.start(in: TimeZone(identifier: "UTC")!).addingTimeInterval(TimeInterval(time))
        let around = Set([zone.secondsFromGMT(for: wall.addingTimeInterval(-86400)), zone.secondsFromGMT(for: wall.addingTimeInterval(86400))])
        let valid = around.filter { zone.secondsFromGMT(for: wall.addingTimeInterval(TimeInterval(-$0))) == $0 }.sorted(by: >)
        return valid.isEmpty ? [zone.secondsFromGMT(for: wall.addingTimeInterval(-86400))] : valid
    }

    static func suffix(_ offset: Int) -> String {
        String(format: "%@%02d:%02d", offset < 0 ? "-" : "+", abs(offset) / 3600, abs(offset) / 60 % 60)
    }

    static func noonOffset(_ day: DayKey, in zone: TimeZone) -> Int {
        zone.secondsFromGMT(for: day.start(in: zone).addingTimeInterval(12 * 3600))
    }
}
