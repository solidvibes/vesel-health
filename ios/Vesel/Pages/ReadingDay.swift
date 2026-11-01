import SwiftUI
import VeselCore
import VeselStorage

/// One day of the 5-minute heart rate, with the sleep inside it, read for the day on screen.
@MainActor
@Observable
final class ReadingDayModel {
    struct Periods {
        let day: DayKey
        let points: [ReadingPoint]
        /// The day's own number, worked out from these periods: `hr.dayRange`.
        let metric: ComputedMetric?
    }

    private(set) var periods: Periods?
    private var loadedSpans: (day: DayKey, spans: [ClosedRange<Date>])?
    /// Today's latest stored reading, for the heart rate page's Now row; nil on another day.
    private(set) var latest: HeartRateSample?
    /// The time `-VeselScrub` asks for, once.
    let takeLaunchScrub: () -> ScrubTime?
    private let reads = ReadProblem()
    private let database: AppDatabase
    private let clock: any VeselClock

    init(database: AppDatabase, clock: any VeselClock, takeLaunchScrub: @escaping () -> ScrubTime? = { nil }) {
        self.database = database
        self.clock = clock
        self.takeLaunchScrub = takeLaunchScrub
    }

    var zone: TimeZone { clock.timeZone }
    /// A read failed; the screen shows its one "Couldn't show this" card.
    var readProblem: Bool { reads.isShown }

    func loaded(_ day: DayKey) -> Periods? { periods?.day == day ? periods : nil }

    func spans(_ day: DayKey) -> [ClosedRange<Date>]? { loadedSpans?.day == day ? loadedSpans?.spans : nil }

    func isReady(_ day: DayKey) -> Bool {
        loaded(day) != nil && spans(day) != nil
    }

    func observe(_ day: DayKey) async {
        async let periods: Void = observePeriods(day)
        async let spans: Void = observeSpans(day)
        _ = await (periods, spans)
    }

    /// Follows today's latest reading; does nothing for another day.
    func observeLatest(_ day: DayKey) async {
        let today = clock.today
        guard day == today else { return }
        await reads.observe {
            for try await snapshot in database.observeToday(day: today, today: today) { latest = snapshot.latestHeartRate }
        }
    }

    private func observePeriods(_ day: DayKey) async {
        await reads.observe {
            for try await value in database.observeHeartRatePeriods(endingOn: day, days: 1, zone: zone) {
                periods = await Self.group(value, day: day, zone: zone)
            }
        }
    }

    /// Off the main thread, like every series worked out on read.
    @concurrent nonisolated private static func group(_ value: [FiveMinuteMean], day: DayKey, zone: TimeZone) async -> Periods {
        let computedAt = day.adding(days: 1).start(in: zone)
        let metric = DailyHeartRate.days(periods: value, zone: zone, computedAt: computedAt).first
        return Periods(day: day, points: value.map { ReadingPoint(time: $0.start, value: $0.mean) }, metric: metric)
    }

    private func observeSpans(_ day: DayKey) async {
        await reads.observe {
            for try await value in database.observeSleepSpans(day: day, zone: zone) {
                loadedSpans = (day, value)
            }
        }
    }
}

/// A day's 5-minute line from 00:00 to 24:00, sleep shaded behind it. A finger on it replaces the page's header (`scrubText`).
struct ReadingDayChart: View {
    let day: DayKey
    let points: [ReadingPoint]
    let spans: [ClosedRange<Date>]
    let zone: TimeZone
    let unit: String
    let color: Color
    let format: (Double) -> String
    /// VoiceOver's label, without the sleep part.
    let spokenLabel: String
    let takeLaunchScrub: () -> ScrubTime?
    var scrub: ChartScrubStyle = .immediate
    @Binding var selection: Date?

    /// The reading nearest `moment`: its clock time and "72 bpm", or "no reading" in a gap.
    static func scrubText(at moment: Date, points: [ReadingPoint], zone: TimeZone, unit: String, format: (Double) -> String) -> (time: String, reading: String)
    {
        let reading = points.nearest(to: moment, within: HeartRateSample.lineGap / 2).map { "\(format($0.value)) \(unit)" } ?? "no reading"
        return (Formatters.clock(moment, zone: zone), reading)
    }

    var body: some View {
        let start = day.start(in: zone)
        let domain = start...day.adding(days: 1).start(in: zone)
        let marks = Self.marks(of: start, zone: zone)
        let text = selection.map { moment -> String in
            let found = Self.scrubText(at: moment, points: points, zone: zone, unit: unit, format: format)
            return "\(found.time) · \(found.reading)"
        }
        VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
            ReadingLineChart(
                points: points, domain: domain, marks: marks, zone: zone, unit: unit, color: color, format: format, shaded: spans, scrub: scrub,
                selection: $selection)
            if !spans.isEmpty {
                Text("Shaded: asleep")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Palette.mutedText)
            }
        }
        .scrubAccessibility($selection, domain: domain, label: label, value: text ?? "")
        .onAppear {
            guard selection == nil else { return }
            selection = takeLaunchScrub()?.moment(in: domain, zone: zone)
        }
    }

    /// 00, 06, 12 and 18 on the wall clock.
    private static func marks(of start: Date, zone: TimeZone) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return [0, 6, 12, 18].compactMap { calendar.date(bySettingHour: $0, minute: 0, second: 0, of: start) }
    }

    private var label: String {
        let asleep = spans.map { "asleep \(Formatters.clock($0.lowerBound, zone: zone)) to \(Formatters.clock($0.upperBound, zone: zone))" }
        return ([spokenLabel] + asleep).joined(separator: ", ")
    }
}

/// "How it's worked out": a row that opens in place onto the explanations.
struct HowItsWorkedOutRow: View {
    /// False inside a card that already is one.
    var framed = true
    var title = "How it's worked out"
    let explanations: [Explanation]
    /// One name per explanation, shown when there is more than one.
    var labels: [String] = []
    /// A worked-out line after the explanations (the share of a sleep stage, the usual range's method).
    var note: String?
    /// A line before the explanations (the body measure heart fitness used).
    var lead: String?
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if framed {
            GlassCard { content }
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
            Button {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { expanded.toggle() }
            } label: {
                HStack {
                    Text(title)
                        .font(Theme.Typography.heading)
                        .foregroundStyle(Theme.Palette.text)
                    Spacer(minLength: Theme.Spacing.s8)
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Palette.mutedText)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: Theme.Size.tapTarget)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows how it's worked out")
            if expanded {
                if let lead {
                    Text(lead)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(explanations.enumerated()), id: \.offset) { index, explanation in
                    if index > 0 { Divider() }
                    if explanations.count > 1, labels.indices.contains(index) {
                        Text(labels[index])
                            .font(Theme.Typography.label)
                            .foregroundStyle(Theme.Palette.mutedText)
                    }
                    ExplanationView(explanation: explanation)
                }
                if let note {
                    if !explanations.isEmpty { Divider() }
                    Text(note)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
