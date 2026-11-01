import SwiftUI
import VeselCore

/// The night's stages with the overnight heart rate under them. A finger on either replaces the page's header (`scrubText`).
struct SleepNightChart: View {
    let sleep: SleepNight
    /// The night's 24/7 heart rate; nil while it is being read.
    let heartRates: [HeartRateSample]?
    let zone: TimeZone
    /// `-VeselScrub`, handed out once.
    let takeLaunchScrub: () -> ScrubTime?
    var scrub: ChartScrubStyle = .immediate
    @Binding var selection: Date?
    @Environment(\.dynamicTypeSize) private var typeSize

    /// "Deep · 51 bpm", "Deep · no reading", or without the bpm part when the night has no heart rate; and the clock time.
    static func scrubText(at moment: Date, sleep: SleepNight, heartRates: [HeartRateSample]?, zone: TimeZone) -> (time: String, reading: String) {
        var parts: [String] = []
        if let state = sleep.state(at: moment) { parts.append(SleepStagesChart.label(state)) }
        if let heartRates, !heartRates.isEmpty {
            parts.append(heartRates.nearest(to: moment, within: HeartRateSample.lineGap / 2).map { "\($0.bpm) bpm" } ?? "no reading")
        }
        return (Formatters.clock(moment, zone: zone), parts.isEmpty ? "—" : parts.joined(separator: " · "))
    }

    var body: some View {
        let domain = sleep.start...sleep.end
        let marks = Self.hourMarks(sleep, zone: zone)
        let text = selection.map { moment -> String in
            let found = Self.scrubText(at: moment, sleep: sleep, heartRates: heartRates, zone: zone)
            return "\(found.time) · \(found.reading)"
        }
        Grid(alignment: .trailing, horizontalSpacing: Theme.Spacing.s8, verticalSpacing: Theme.Spacing.s8) {
            GridRow {
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(SleepStagesChart.stages(of: sleep), id: \.self) { state in
                        Text(SleepStagesChart.label(state))
                            .frame(maxHeight: .infinity)
                    }
                }
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Palette.mutedText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                SleepStagesChart(night: sleep, marks: marks, selection: $selection, scrub: scrub)
            }
            GridRow {
                heartRateRange
                heartRateChart(domain: domain, marks: marks)
            }
        }
        .scrubAccessibility(
            $selection, domain: domain,
            label: "Sleep stages and heart rate, swipe up or down to move through the night",
            value: text ?? (heartRates?.isEmpty == true ? "No heart rate recorded this night." : "")
        )
        .onAppear {
            guard selection == nil else { return }
            selection = takeLaunchScrub()?.moment(in: domain, zone: zone)
        }
    }

    private var bpmRange: ClosedRange<Int>? {
        guard let low = heartRates?.map(\.bpm).min(), let high = heartRates?.map(\.bpm).max() else { return nil }
        return low == high ? (low - 1)...(high + 1) : low...high
    }

    /// The lowest and highest beat of the night, beside the line: the line's own scale.
    @ViewBuilder private var heartRateRange: some View {
        if let bpmRange {
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(bpmRange.upperBound)")
                Spacer(minLength: 0)
                Text("\(bpmRange.lowerBound)")
                Text("bpm")
            }
            .font(Theme.Typography.small)
            .foregroundStyle(Theme.Palette.mutedText)
            .frame(maxHeight: .infinity)
        } else {
            Color.clear.frame(width: 0, height: 0)
        }
    }

    @ViewBuilder private func heartRateChart(domain: ClosedRange<Date>, marks: [Date]) -> some View {
        if let heartRates {
            if heartRates.isEmpty {
                Text("No heart rate recorded this night.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ReadingLineChart(
                    points: heartRates.map { ReadingPoint(time: $0.time, value: Double($0.bpm)) }, domain: domain, marks: marks, zone: zone,
                    yDomain: bpmRange.map { Double($0.lowerBound)...Double($0.upperBound) }, height: 100, scrub: scrub, selection: $selection
                )
            }
        } else {
            SkeletonBlock(height: typeSize.isAccessibilitySize ? 200 : 100)
        }
    }

    /// Every second whole hour on the local clock inside the night; when the clocks go back, a repeated hour is marked once.
    private static func hourMarks(_ sleep: SleepNight, zone: TimeZone) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        var marks: [Date] = []
        var hour = calendar.dateInterval(of: .hour, for: sleep.start)?.start ?? sleep.start
        while hour <= sleep.end {
            let clockHour = calendar.component(.hour, from: hour)
            let repeated = marks.last.map { calendar.component(.hour, from: $0) == clockHour } ?? false
            if hour >= sleep.start, clockHour % 2 == 0, !repeated { marks.append(hour) }
            guard let next = calendar.date(byAdding: .hour, value: 1, to: hour) else { break }
            hour = next
        }
        return marks
    }
}
