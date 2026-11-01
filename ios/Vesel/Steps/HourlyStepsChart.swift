import Charts
import SwiftUI
import VeselCore

/// Steps per hour of the day, one bar per wall-clock hour with steps, in the muted text colour. No goal line.
/// The x axis is real moments: each bar starts at its hour's wall-clock start in the day's zone, so a day of 23 or 25 hours is right.
private struct HourlyStepsBars: ChartContent {
    let hour: HourlySteps.Hour
    let day: DayKey
    let zone: TimeZone
    let selectedHour: Int?
    /// Bars never run past this moment (the hour in progress is cut at now).
    var limit: Date = .distantFuture

    var body: some ChartContent {
        let start = HourlyStepsTime.start(of: hour.hour, day: day, zone: zone)
        RectangleMark(
            xStart: .value("From", start.addingTimeInterval(240)),
            xEnd: .value("To", min(start.addingTimeInterval(3360), limit)),
            yStart: .value("None", 0),
            yEnd: .value("Steps", hour.steps)
        )
        .foregroundStyle(Theme.Palette.mutedText.opacity(selectedHour == nil || selectedHour == hour.hour ? 1 : 0.35))
        .cornerRadius(2)
    }
}

enum HourlyStepsTime {
    static func calendar(_ zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    /// The first moment of the wall-clock hour `hour` (0 to 23) on `day`.
    static func start(of hour: Int, day: DayKey, zone: TimeZone) -> Date {
        calendar(zone).date(bySettingHour: hour, minute: 0, second: 0, of: day.start(in: zone)) ?? day.start(in: zone)
    }

    static func hour(of moment: Date, zone: TimeZone) -> Int {
        calendar(zone).component(.hour, from: moment)
    }
}

/// The page's chart: a finger moves a line over the bars; the page's header reads that hour.
struct HourlyStepsChart: View {
    let hours: [HourlySteps.Hour]
    let day: DayKey
    let zone: TimeZone
    let takeLaunchScrub: () -> ScrubTime?
    var scrub: ChartScrubStyle = .immediate
    @Binding var selection: Date?
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The steps in the hour `moment` falls in: "1,204 steps", "no steps" for an hour with none.
    static func scrubText(at moment: Date, hours: [HourlySteps.Hour], zone: TimeZone) -> (hour: String, steps: String) {
        let hour = HourlyStepsTime.hour(of: moment, zone: zone)
        let steps = hours.first { $0.hour == hour }?.steps
        return (Formatters.hourRange(hour), steps.map { "\(Formatters.steps($0)) steps" } ?? "no steps")
    }

    var body: some View {
        let start = day.start(in: zone)
        let end = day.adding(days: 1).start(in: zone)
        let domain = start...end
        let selectedHour = selection.map { HourlyStepsTime.hour(of: $0, zone: zone) }
        let text = selection.map { moment -> String in
            let found = Self.scrubText(at: moment, hours: hours, zone: zone)
            return "\(found.hour) · \(found.steps)"
        }
        Chart {
            ForEach(hours, id: \.hour) { HourlyStepsBars(hour: $0, day: day, zone: zone, selectedHour: selectedHour) }
            if let selectedHour { ScrubRule(date: HourlyStepsTime.start(of: selectedHour, day: day, zone: zone).addingTimeInterval(1800)) }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: 0...max(hours.map(\.steps).max() ?? 0, 1))
        .chartScrub($selection, style: scrub)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                if !typeSize.isAccessibilitySize {
                    AxisValueLabel { if let number = value.as(Int.self) { Text(Formatters.steps(number)) } }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: ([0, 6, 12, 18].map { HourlyStepsTime.start(of: $0, day: day, zone: zone) }) + [end]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let moment = value.as(Date.self) {
                        Text(moment == end ? "24" : String(format: "%02d", HourlyStepsTime.hour(of: moment, zone: zone)))
                    }
                }
            }
        }
        .frame(height: typeSize.isAccessibilitySize ? 360 : 200)
        .scrubAccessibility($selection, domain: domain, step: 3600, label: "Steps per hour", value: text ?? "")
        .onAppear {
            guard selection == nil else { return }
            selection = takeLaunchScrub()?.moment(in: domain, zone: zone)
        }
    }
}

/// Bars only, no axes and no finger: Journal's card (the whole day) and Today's card (the day so far, `end` being now).
struct HourlyStepsGlance: View {
    let hours: [HourlySteps.Hour]
    let day: DayKey
    let zone: TimeZone
    /// Where the bars stop; the whole day when nil.
    var until: Date?
    var height: CGFloat = 48

    var body: some View {
        let start = day.start(in: zone)
        let dayEnd = day.adding(days: 1).start(in: zone)
        let end = until.map { max(min($0, dayEnd), start.addingTimeInterval(3600)) } ?? dayEnd
        let shown = hours.filter { HourlyStepsTime.start(of: $0.hour, day: day, zone: zone) < end }
        Chart {
            ForEach(shown, id: \.hour) { HourlyStepsBars(hour: $0, day: day, zone: zone, selectedHour: nil, limit: end) }
        }
        .chartXScale(domain: start...end)
        .chartYScale(domain: 0...max(shown.map(\.steps).max() ?? 0, 1))
        .chartPlotStyle { $0.clipped() }
        .chartYAxis(.hidden)
        .chartXAxis(.hidden)
        .frame(height: height)
    }
}
