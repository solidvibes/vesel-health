import Foundation
import VeselCore

/// The screen's own line for the day shown in a meaning sheet: numbers and words about this day, never the meaning itself.
enum YoursText {
    /// "Last night" for today's night, else "On Tue, Oct 27".
    static func night(_ day: DayKey, today: DayKey, zone: TimeZone) -> String {
        day == today ? "Last night" : "On \(Formatters.day(day, zone: zone))"
    }

    /// "Today" or "On Tue, Oct 27".
    static func day(_ day: DayKey, today: DayKey, zone: TimeZone) -> String {
        day == today ? "Today" : "On \(Formatters.day(day, zone: zone))"
    }

    /// "Last night: 48 ms, higher than your usual (34–52 ms)." Skin temperature: "34.6 °C, +0.2 °C against your usual night."
    /// Sleep: "Last night: 7 h 05 m asleep, within your normal (6 h 40 m–9 h 10 m).", the Sleep line's normal from `InRange.sleep`.
    static func contributor(_ reading: ContributorReading, when: String, units: Units = .metric) -> String {
        let value = reading.contributor == .sleep ? "\(reading.valueText()) asleep" : reading.valueText(units: units)
        guard let range = reading.range else { return "\(when): \(value). \(LearningText.nights(reading.nights))." }
        if reading.contributor == .sleep {
            return "\(when): \(value), \(sleepWords(InRange.sleep(reading)))."
        }
        if reading.contributor == .skinTemperature, let difference = reading.differenceText(units: units) {
            return "\(when): \(value), \(difference) against your usual night."
        }
        let words = vsUsual(
            value: reading.value, range: range, nights: reading.nights, text: { reading.contributor.text($0, units: units) }
        )
        return "\(when): \(value), \(words)."
    }

    /// "within your normal (6 h 40 m–9 h 10 m)", "shorter than …", "longer than …".
    private static func sleepWords(_ line: LineVerdict) -> String {
        let span = "\(DurationText.hoursMinutes(minutes: line.normal.low ?? 0))–\(DurationText.hoursMinutes(minutes: line.normal.high ?? 0))"
        switch line.state {
        case .below: return "shorter than your normal (\(span))"
        case .above: return "longer than your normal (\(span))"
        default: return "within your normal (\(span))"
        }
    }

    /// "higher than your usual (34–52 ms)", or the learning wording while there is no usual yet.
    static func vsUsual(value: Double, range: PersonalRange?, nights: Int, text: (Double) -> String) -> String {
        guard let range else { return LearningText.nights(nights) }
        let span = span(of: range, text)
        switch range.verdict(of: value) {
        case .wellBelow: return "much lower than your usual (\(span))"
        case .lower: return "lower than your usual (\(span))"
        case .usual, .learning: return "within your usual (\(span))"
        case .higher: return "higher than your usual (\(span))"
        case .wellAbove: return "much higher than your usual (\(span))"
        }
    }

    /// "34–52 ms": a plain number and unit says the unit once; a time like "7 h 50 m" is written out.
    private static func span(of range: PersonalRange, _ text: (Double) -> String) -> String {
        let low = text(range.low)
        let high = text(range.high)
        let parts = high.split(separator: " ")
        guard parts.count == 2, let unit = parts.last, low.hasSuffix(" \(unit)") else { return "\(low)–\(high)" }
        return "\(low.dropLast(unit.count + 1))–\(high)"
    }
}
