import Charts
import SwiftUI
import VeselCore

/// Journal's stress glance: the hour's middle level per hour of the day, coloured calm / moderate / high, bars only, 48 pt tall.
struct HourlyStressChart: View {
    let hours: [StressHour]
    let day: DayKey
    let zone: TimeZone
    /// Drawn behind the bars; a bar's VoiceOver value names the sport.
    var workouts: [WorkoutSpan] = []

    static func word(_ band: StressLevel) -> String { band.word.capitalizedFirst }

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
        let domain = start(StressThresholds.daytimeHours.lowerBound)...start(StressThresholds.daytimeHours.upperBound)
        Chart {
            WorkoutBlocks(ranges: workouts.clipped(to: domain), top: 100)
            ForEach(hours) { hour in
                BarMark(
                    x: .value("Hour", start(hour.hour), unit: .hour),
                    y: .value("Level", max(hour.level, 3))
                )
                .foregroundStyle(by: .value("Stress", Self.word(hour.band)))
                .cornerRadius(3)
                .accessibilityLabel(Formatters.hourRange(hour.hour))
                .accessibilityValue(
                    "\(Self.word(hour.band)), level \(Formatters.whole(hour.level)) of 100"
                        + (Self.workout(in: hour.hour, day: day, zone: zone, workouts: workouts).map { ", during a \($0)" } ?? ""))
            }
        }
        .chartForegroundStyleScale(domain: ["Calm", "Moderate", "High"], range: [Theme.Palette.success, Theme.Palette.stress, Theme.Palette.error])
        .chartXScale(domain: domain)
        .chartYScale(domain: 0...100)
        .chartLegend(.hidden)
        .chartYAxis(.hidden)
        .chartXAxis(.hidden)
        .frame(height: 48)
    }
}
