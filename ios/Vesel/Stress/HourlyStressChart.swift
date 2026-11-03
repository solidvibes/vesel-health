import Charts
import SwiftUI
import VeselCore

/// Stress level per hour of the day, coloured calm / moderate / high, with a legend (colour is never the only sign).
/// On the page a finger moves a line over the bars and the page's header reads that hour (`scrubText`).
struct HourlyStressChart: View {
    let hours: [StressHour]
    /// Hours with beats but no bar; the scrub text says why.
    var emptyHours: [StressEmptyHour] = []
    let day: DayKey
    let zone: TimeZone
    /// Drawn behind the bars; a bar's VoiceOver value and the scrub text name the sport.
    var workouts: [WorkoutSpan] = []
    /// Journal's glance: bars only, no axes, legend or finger, 48 pt tall.
    var compact = false
    var takeLaunchScrub: () -> ScrubTime? = { nil }
    var scrub: ChartScrubStyle = .immediate
    @Binding var selection: Date?
    @Environment(\.dynamicTypeSize) private var typeSize

    static func word(_ band: StressLevel) -> String { band.word.capitalizedFirst }

    /// The hour `moment` falls in and its bar: "High, 72"; for an hour with none "no reading, mostly movement", or
    /// "no reading" when the band recorded nothing.
    static func scrubText(at moment: Date, hours: [StressHour], emptyHours: [StressEmptyHour], zone: TimeZone) -> (hour: String, level: String) {
        let hour = HourlyStepsTime.hour(of: moment, zone: zone)
        let level = hours.first { $0.hour == hour }.map { "\(word($0.band)), \(Formatters.whole($0.level))" }
        let empty = emptyHours.first { $0.hour == hour }.map { "no reading, \($0.reason.phrase)" }
        return (Formatters.hourRange(hour), level ?? empty ?? "no reading")
    }

    /// The workout that shares time with `hour`: "ride".
    static func workout(in hour: Int, day: DayKey, zone: TimeZone, workouts: [WorkoutSpan]) -> String? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        guard let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day.start(in: zone)) else { return nil }
        return workouts.word(overlapping: start...start.addingTimeInterval(3600))
    }

    private func start(_ hour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day.start(in: zone))!
    }

    var body: some View {
        if compact {
            bars
                .chartLegend(.hidden)
                .chartYAxis(.hidden)
                .chartXAxis(.hidden)
                .frame(height: 48)
        } else {
            full
        }
    }

    private var bars: some View {
        let selectedHour = selection.map { HourlyStepsTime.hour(of: $0, zone: zone) }
        let domain = start(StressThresholds.daytimeHours.lowerBound)...start(StressThresholds.daytimeHours.upperBound)
        return Chart {
            WorkoutBlocks(ranges: workouts.clipped(to: domain), top: 100)
            ForEach(hours) { hour in
                BarMark(
                    x: .value("Hour", start(hour.hour), unit: .hour),
                    y: .value("Level", max(hour.level, 3))
                )
                .foregroundStyle(by: .value("Stress", Self.word(hour.band)))
                .opacity(selectedHour == nil || selectedHour == hour.hour ? 1 : 0.35)
                .cornerRadius(3)
                .accessibilityLabel(Formatters.hourRange(hour.hour))
                .accessibilityValue(
                    "\(Self.word(hour.band)), level \(Formatters.whole(hour.level)) of 100"
                        + (Self.workout(in: hour.hour, day: day, zone: zone, workouts: workouts).map { ", during a \($0)" } ?? ""))
            }
            if let selectedHour { ScrubRule(date: start(selectedHour).addingTimeInterval(1800)) }
        }
        .chartForegroundStyleScale(domain: ["Calm", "Moderate", "High"], range: [Theme.Palette.success, Theme.Palette.stress, Theme.Palette.error])
        .chartXScale(domain: domain)
        .chartYScale(domain: 0...100)
    }

    private var full: some View {
        let domain = start(StressThresholds.daytimeHours.lowerBound)...start(StressThresholds.daytimeHours.upperBound)
        let text = selection.map { moment -> String in
            let found = Self.scrubText(at: moment, hours: hours, emptyHours: emptyHours, zone: zone)
            let workout = Self.workout(in: HourlyStepsTime.hour(of: moment, zone: zone), day: day, zone: zone, workouts: workouts)
            return "\(found.hour) · \(found.level)" + (workout.map { ", during a \($0)" } ?? "")
        }
        return
            bars
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
                AxisMarks(values: stride(from: StressThresholds.daytimeHours.lowerBound, to: StressThresholds.daytimeHours.upperBound, by: 4).map(start)) {
                    value in
                    AxisGridLine()
                    AxisValueLabel { if let date = value.as(Date.self) { Text(Formatters.hourLabel(date, zone: zone)) } }
                }
            }
            .chartLegend(position: .bottom, alignment: .leading, spacing: Theme.Spacing.s12)
            .frame(height: typeSize.isAccessibilitySize ? 360 : 200)
            .scrubAccessibility($selection, domain: domain, step: 3600, label: "Stress per hour", value: text ?? "")
            .onAppear {
                guard selection == nil else { return }
                selection = takeLaunchScrub()?.moment(in: domain, zone: zone)
            }
    }
}
