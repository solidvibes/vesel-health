import Charts
import SwiftUI
import VeselCore

/// One reading at a moment, in the units the chart is labelled in.
struct ReadingPoint: Identifiable, Equatable {
    let time: Date
    let value: Double
    var id: Date { time }
}

extension Array where Element == ReadingPoint {
    /// The point closest in time to `date`, if one is within `limit` seconds (a tie goes to the earlier one). Needs the points in time order.
    func nearest(to date: Date, within limit: TimeInterval) -> ReadingPoint? {
        var low = 0
        var high = count
        while low < high {
            let mid = (low + high) / 2
            if self[mid].time < date { low = mid + 1 } else { high = mid }
        }
        let candidates = [low - 1, low].filter { indices.contains($0) }.map { self[$0] }
        let best = candidates.min { abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date)) }
        return best.flatMap { abs($0.time.timeIntervalSince(date)) <= limit ? $0 : nil }
    }
}

extension Array where Element == WorkoutSpan {
    /// The noun of the workout `moment` falls in ("ride").
    func word(at moment: Date) -> String? { first { $0.range.contains(moment) }?.word }

    /// The noun of the workout that shares time with `range`, touching ends left out.
    func word(overlapping range: ClosedRange<Date>) -> String? {
        first { $0.range.lowerBound < range.upperBound && range.lowerBound < $0.range.upperBound }?.word
    }

    /// Each workout's time inside `domain`.
    func clipped(to domain: ClosedRange<Date>) -> [ClosedRange<Date>] {
        compactMap { span in
            let start = Swift.max(span.range.lowerBound, domain.lowerBound)
            let end = Swift.min(span.range.upperBound, domain.upperBound)
            return start < end ? start...end : nil
        }
    }
}

/// A workout's time behind a chart's marks: workout purple at 18 % with a 3 pt full-colour top edge at `top`, so it is never
/// told apart by colour alone (the scrub text and VoiceOver name the sport).
struct WorkoutBlocks: ChartContent {
    let ranges: [ClosedRange<Date>]
    let top: Double

    var body: some ChartContent {
        ForEach(Array(ranges.enumerated()), id: \.offset) { _, range in
            RectangleMark(xStart: .value("Workout from", range.lowerBound), xEnd: .value("Workout to", range.upperBound))
                .foregroundStyle(Theme.Palette.workout.opacity(0.18))
            RuleMark(xStart: .value("Workout from", range.lowerBound), xEnd: .value("Workout to", range.upperBound), y: .value("Top", top))
                .lineStyle(StrokeStyle(lineWidth: 3))
                .foregroundStyle(Theme.Palette.workout)
                .offset(y: 1.5)
        }
    }
}

/// Every line of readings over time: heart rate, skin temperature. A silence longer than `HeartRateSample.lineGap` is a gap in the line,
/// never a guess; a lone reading is a dot. With `yDomain` the y axis is hidden and the caller labels it. `shaded` stretches (sleep) and
/// `workouts` sit behind the line.
struct ReadingLineChart: View {
    let points: [ReadingPoint]
    let domain: ClosedRange<Date>
    let marks: [Date]
    let zone: TimeZone
    var unit = "bpm"
    var color: Color = Theme.Palette.primary
    var format: (Double) -> String = { Formatters.whole($0) }
    var shaded: [ClosedRange<Date>] = []
    var workouts: [WorkoutSpan] = []
    var yDomain: ClosedRange<Double>?
    var height: CGFloat = 160
    var scrub: ChartScrubStyle = .immediate
    @Binding var selection: Date?
    @Environment(\.dynamicTypeSize) private var typeSize

    private struct Segment: Identifiable {
        let id: Int
        let points: [ReadingPoint]
    }

    private var segments: [Segment] {
        var result: [[ReadingPoint]] = []
        for point in points {
            if let last = result.last?.last, point.time.timeIntervalSince(last.time) <= HeartRateSample.lineGap {
                result[result.count - 1].append(point)
            } else {
                result.append([point])
            }
        }
        return result.enumerated().map { Segment(id: $0.offset, points: $0.element) }
    }

    /// Fitted to the readings: shaded stretches with no y of their own would otherwise pull the axis down to zero.
    private var fittedDomain: ClosedRange<Double> {
        guard let low = points.map(\.value).min(), let high = points.map(\.value).max() else { return 0...1 }
        let pad = Swift.max((high - low) * 0.1, 0.5)
        return (low - pad)...(high + pad)
    }

    var body: some View {
        if let yDomain {
            chart.chartYScale(domain: yDomain).chartYAxis(.hidden)
        } else {
            chart
                .chartYScale(domain: fittedDomain)
                .chartYAxisLabel(unit)
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        if !typeSize.isAccessibilitySize {
                            AxisValueLabel { if let number = value.as(Double.self) { Text(format(number)) } }
                        }
                    }
                }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(Array(shaded.enumerated()), id: \.offset) { _, span in
                RectangleMark(xStart: .value("From", span.lowerBound), xEnd: .value("To", span.upperBound))
                    .foregroundStyle(Theme.Palette.sleep.opacity(0.12))
            }
            WorkoutBlocks(ranges: workouts.clipped(to: domain), top: (yDomain ?? fittedDomain).upperBound)
            ForEach(segments) { segment in
                ForEach(segment.points) { point in
                    LineMark(x: .value("Time", point.time), y: .value(unit, point.value), series: .value("Stretch", segment.id))
                        .foregroundStyle(color)
                }
                if segment.points.count == 1, let point = segment.points.first {
                    PointMark(x: .value("Time", point.time), y: .value(unit, point.value))
                        .foregroundStyle(color)
                        .symbolSize(12)
                }
            }
            if let selection {
                ScrubRule(date: selection)
                if let reading = points.nearest(to: selection, within: HeartRateSample.lineGap / 2) {
                    ScrubDot(date: reading.time, value: reading.value, color: color)
                }
            }
        }
        .chartXScale(domain: domain)
        .chartScrub($selection, style: scrub)
        .chartXAxis {
            AxisMarks(values: marks) { value in
                AxisGridLine()
                AxisValueLabel { if let date = value.as(Date.self) { Text(Formatters.hourLabel(date, zone: zone)) } }
            }
        }
        .frame(height: typeSize.isAccessibilitySize ? height * 2 : height)
    }
}

#if DEBUG
#Preview {
    let start = Date(timeIntervalSince1970: 1_792_886_400)
    let points = (0..<48).map { ReadingPoint(time: start.addingTimeInterval(Double($0) * 1800), value: 62 + 14 * sin(Double($0) / 5)) }
    ReadingLineChart(
        points: points, domain: start...start.addingTimeInterval(24 * 3600), marks: [start, start.addingTimeInterval(12 * 3600)], zone: .gmt,
        shaded: [start...start.addingTimeInterval(8 * 3600)], selection: .constant(nil)
    )
    .padding(Theme.Spacing.edge)
    .background { BlobBackground() }
}
#endif
