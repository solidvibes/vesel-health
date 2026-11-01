import Charts
import SwiftUI
import VeselCore

/// One signal on Body: its title (opens its meaning), the latest night's value and a chart of the range. The body (value and chart) opens what `open` wraps it in; the title is never inside it.
struct BodyCard<Open: View>: View {
    let latest: String?
    let chart: SignalChart
    /// The learning wording, under the chart, while the normal is still being worked out.
    let note: String?
    /// What VoiceOver says for the latest value and its normal.
    let spoken: String
    let title: TermTitle
    /// Wraps the card body in what it does when tapped: a `NavigationLink`.
    @ViewBuilder let open: (AnyView) -> Open

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
                HStack(spacing: Theme.Spacing.s8) {
                    title
                    open(AnyView(value))
                        .buttonStyle(.plain)
                        .accessibilityLabel(spoken)
                }
                .frame(minHeight: Theme.Size.row)
                if !chart.points.isEmpty {
                    open(AnyView(chart))
                        .buttonStyle(.plain)
                        .accessibilityHidden(true)
                }
                if let note {
                    Text(TermLink.text(note, linking: "usual range", to: .usualRange))
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Palette.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var value: some View {
        HStack(spacing: Theme.Spacing.s8) {
            Spacer(minLength: 0)
            Text(latest ?? "No readings")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.mutedText)
                .multilineTextAlignment(.trailing)
            Image(systemName: "chevron.right")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Palette.mutedText)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: Theme.Size.row, alignment: .trailing)
        .contentShape(.rect)
    }
}

/// A signal over the range: a value per night (a line with points; stress, steps and sleep as bars) over a shaded band that follows each night's own normal.
/// Points outside the band are hollow. The compact form is Body's glance; the full one is the page's W, M and 3M chart, which a finger
/// scrubs after a short hold and a tap on a day opens.
struct SignalChart: View {
    let kind: TrendKind
    let points: [TrendPoint]
    let domain: ClosedRange<Date>
    let ticks: [TrendTick]
    let units: Units
    /// The dashed median of the nights so far, while the normal is still being worked out.
    let settlingMedian: Double?
    let zone: TimeZone
    var compact = true
    /// The finger on the chart: the moment it touches. Nil on a glance, which has no gestures.
    var selection: Binding<Date?>?
    /// The day drawn in full while the others fade.
    var highlighted: DayKey?
    var onPickDay: ((DayKey) -> Void)?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let values = points.flatMap { [$0.value, $0.low ?? $0.value, $0.high ?? $0.value] } + [settlingMedian].compactMap { $0 }
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let pad = Swift.max((high - low) * 0.15, 0.5)
        let size: CGFloat = compact ? (typeSize.isAccessibilitySize ? 240 : 120) : 240
        let selected = selection?.wrappedValue.flatMap { moment in points.first { $0.day == DayKey(moment, in: zone) } }
        let chart = Chart {
            if let settlingMedian { SettlingRule(median: settlingMedian, color: kind.color) }
            if kind.isBars {
                ForEach(points) { point in
                    if let high = point.high {
                        RectangleMark(
                            xStart: .value("From", point.start), xEnd: .value("To", point.end), yStart: .value("Normal low", point.low ?? 0),
                            yEnd: .value("Normal high", high)
                        )
                        .foregroundStyle(kind.bandColor.opacity(0.18))
                    }
                }
                ForEach(points) { point in
                    BarMark(x: .value("Day", point.start, unit: .day), y: .value(kind.title, point.value))
                        .foregroundStyle(kind.color.opacity(point.isPartial ? 0.45 : emphasis(point)))
                        .cornerRadius(compact ? 2 : 3)
                }
            } else {
                ForEach(Array(points.runs.enumerated()), id: \.offset) { index, run in
                    ForEach(run) { point in
                        if let low = point.low, let high = point.high {
                            AreaMark(
                                x: .value("Day", point.start), yStart: .value("Normal low", low), yEnd: .value("Normal high", high),
                                series: .value("Normal", index)
                            )
                            .foregroundStyle(kind.color.opacity(0.18))
                        }
                    }
                    ForEach(run) { point in
                        LineMark(x: .value("Day", point.start), y: .value(kind.title, point.value), series: .value("Run", index))
                            .foregroundStyle(kind.color)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round))
                            .opacity(highlighted == nil ? 1 : 0.35)
                    }
                }
                ForEach(points) { point in
                    if point.isOutsideNormal {
                        PointMark(x: .value("Day", point.start), y: .value(kind.title, point.value))
                            .foregroundStyle(kind.color.opacity(emphasis(point)))
                            .symbol(Circle().strokeBorder(lineWidth: 1.5))
                            .symbolSize(dotSize + 8)
                    } else {
                        PointMark(x: .value("Day", point.start), y: .value(kind.title, point.value))
                            .foregroundStyle(kind.color.opacity(emphasis(point)))
                            .symbolSize(dotSize)
                    }
                }
            }
            if let selected {
                if kind.isBars {
                    ScrubRule(date: selected.start.addingTimeInterval(selected.end.timeIntervalSince(selected.start) / 2))
                } else {
                    ScrubRule(date: selected.start)
                    ScrubDot(date: selected.start, value: selected.value, color: kind.color)
                }
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: yDomain(low: low, high: high, pad: pad))
        .trendAxes(ticks: ticks, yValues: kind == .recovery ? [1, 3, 6] : nil, showsNumbers: !typeSize.isAccessibilitySize)
        .chartYAxisLabel(position: .trailing) { if !compact { Text(kind.axisLabel(units: units)) } }
        .frame(height: size)
        if let selection {
            chart.chartScrub(
                selection,
                style: .holdThenDrag(slot: { Self.slot(of: $0, zone: zone) }, onTap: onPickDay.map { pick in { pick(DayKey($0, in: zone)) } })
            )
        } else {
            chart
        }
    }

    private func emphasis(_ point: TrendPoint) -> Double { highlighted == nil || point.day == highlighted ? 1 : 0.35 }

    /// The day a moment falls on, as a number: the scrub ticks each time it moves to another day.
    static func slot(of moment: Date, zone: TimeZone) -> Int {
        let day = DayKey(moment, in: zone)
        return day.year * 10_000 + day.month * 100 + day.day
    }

    /// Small dots on the compact cards and over 3 months, where there are many.
    private var dotSize: Double { compact || domain.upperBound.timeIntervalSince(domain.lowerBound) > 60 * 86_400 ? 12 : 30 }

    private func yDomain(low: Double, high: Double, pad: Double) -> ClosedRange<Double> {
        if kind == .recovery { return 1...6 }
        if kind.isBars { return 0...Swift.max(high * 1.15, 1) }
        return (low - pad)...(high + pad)
    }
}

extension View {
    /// The charts' axes: a faint grid, 3 numbers on the trailing side (`yValues` when the scale is fixed) and the dates along the bottom (every other date at the largest text sizes).
    func trendAxes(ticks allTicks: [TrendTick], yValues: [Double]?, showsNumbers: Bool) -> some View {
        // At the largest text sizes every other label; a week keeps the inner ones (Tue, Thu, Sat), as the end days' labels don't fit at the edges.
        let ticks =
            showsNumbers
            ? allTicks
            : allTicks.enumerated().filter { tick in
                allTicks.count == PagePeriod.week.days ? tick.offset % 2 == 1 : (allTicks.count - 1 - tick.offset) % 2 == 0
            }.map(\.element)
        return chartYAxis {
            if let yValues {
                AxisMarks(position: .trailing, values: yValues) { _ in
                    AxisGridLine().foregroundStyle(Theme.Palette.mutedText.opacity(0.25))
                    if showsNumbers { AxisValueLabel() }
                }
            } else {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(Theme.Palette.mutedText.opacity(0.25))
                    if showsNumbers { AxisValueLabel() }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: ticks.map(\.date)) { value in
                if let date = value.as(Date.self), let tick = ticks.first(where: { $0.date == date }) {
                    AxisValueLabel(anchor: .top) { Text(tick.label) }
                }
            }
        }
    }
}
