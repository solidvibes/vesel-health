import Charts
import SwiftUI
import VeselCore

/// Every 3-minute reading of the day as its own bar, coloured calm / moderate / high, with a legend (colour is never the only sign).
/// Nothing is drawn where nothing was measured. A finger reads the nearest reading and the page's header shows it (`scrubText`).
struct StressTimelineChart: View {
    let readings: [StressReading]
    let emptyHours: [StressEmptyHour]
    let day: DayKey
    let zone: TimeZone
    /// Drawn behind the bars; the scrub text names the sport.
    var workouts: [WorkoutSpan] = []
    var takeLaunchScrub: () -> ScrubTime? = { nil }
    var scrub: ChartScrubStyle = .immediate
    @Binding var selection: Date?
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The reading `moment` falls in, or the nearest one starting within 3 minutes of it.
    static func reading(at moment: Date, in readings: [StressReading]) -> StressReading? {
        readings
            .filter { abs($0.start.addingTimeInterval(StressThresholds.windowSeconds / 2).timeIntervalSince(moment)) <= StressThresholds.windowSeconds }
            .min { abs($0.start.timeIntervalSince(moment)) < abs($1.start.timeIntervalSince(moment)) }
    }

    /// "14:30–14:33" and "High, 82"; in a gap the finger's clock time and "no reading, mostly movement" (that hour's reason), or
    /// "no reading" when the band recorded nothing.
    static func scrubText(at moment: Date, readings: [StressReading], emptyHours: [StressEmptyHour], zone: TimeZone) -> (time: String, level: String) {
        if let found = reading(at: moment, in: readings) {
            let end = found.start.addingTimeInterval(StressThresholds.windowSeconds)
            return (
                "\(Formatters.clock(found.start, zone: zone))–\(Formatters.clock(end, zone: zone))",
                "\(found.band.word.capitalizedFirst), \(Formatters.whole(found.level))"
            )
        }
        let hour = HourlyStepsTime.hour(of: moment, zone: zone)
        let empty = emptyHours.first { $0.hour == hour }.map { "no reading, \($0.reason.phrase)" }
        return (Formatters.clock(moment, zone: zone), empty ?? "no reading")
    }

    private func start(_ hour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day.start(in: zone))!
    }

    var body: some View {
        let domain = start(StressThresholds.daytimeHours.lowerBound)...start(StressThresholds.daytimeHours.upperBound)
        let selected = selection.flatMap { Self.reading(at: $0, in: readings) }
        let spoken = selection.map { moment -> String in
            let found = Self.scrubText(at: moment, readings: readings, emptyHours: emptyHours, zone: zone)
            return "\(found.time) · \(found.level)" + (workouts.word(at: moment).map { ", during a \($0)" } ?? "")
        }
        return Chart {
            WorkoutBlocks(ranges: workouts.clipped(to: domain), top: 100)
            ForEach(readings, id: \.start) { reading in
                let end: Date = reading.start.addingTimeInterval(StressThresholds.windowSeconds)
                let level: Double = max(reading.level, 3)
                let word: String = reading.band.word.capitalizedFirst
                let shown: Double = selection == nil || selected?.start == reading.start ? 1 : 0.35
                RectangleMark(
                    xStart: .value("Start", reading.start),
                    xEnd: .value("End", end),
                    yStart: .value("Floor", 0.0),
                    yEnd: .value("Level", level)
                )
                .foregroundStyle(by: .value("Stress", word))
                .opacity(shown)
            }
            if let moment = selection {
                ScrubRule(date: selected.map { $0.start.addingTimeInterval(StressThresholds.windowSeconds / 2) } ?? moment)
            }
        }
        .chartForegroundStyleScale(domain: ["Calm", "Moderate", "High"], range: [Theme.Palette.success, Theme.Palette.stress, Theme.Palette.error])
        .chartXScale(domain: domain)
        .chartYScale(domain: 0...100)
        .chartScrub($selection, style: scrub)
        .chartYAxis {
            AxisMarks(values: [0, StressThresholds.moderateFrom, StressThresholds.highFrom, 100]) { value in
                AxisGridLine()
                if !typeSize.isAccessibilitySize {
                    AxisValueLabel { if let number = value.as(Double.self) { Text(Formatters.whole(number)) } }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: stride(from: StressThresholds.daytimeHours.lowerBound, to: StressThresholds.daytimeHours.upperBound, by: 4).map(start)) { value in
                AxisGridLine()
                AxisValueLabel { if let date = value.as(Date.self) { Text(Formatters.hourLabel(date, zone: zone)) } }
            }
        }
        .chartLegend(position: .bottom, alignment: .leading, spacing: Theme.Spacing.s12)
        .frame(height: typeSize.isAccessibilitySize ? 360 : 200)
        .scrubAccessibility($selection, domain: domain, label: "Stress readings", value: spoken ?? "")
        .onAppear {
            guard selection == nil else { return }
            selection = takeLaunchScrub()?.moment(in: domain, zone: zone)
        }
    }
}
