import Charts
import SwiftUI
import VeselCore

/// Polar's sleep phases across the night, one row per stage. The stage names and the time labels are the card's: its
/// grid puts the names beside the rows and the hours under the heart-rate line, so this chart draws neither.
struct SleepStagesChart: View {
    let night: SleepNight
    let marks: [Date]
    @Binding var selection: Date?
    var scrub: ChartScrubStyle = .immediate
    /// Journal's glance: no grid and no scrubbing, 44 pt tall.
    var compact = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private struct Segment: Identifiable {
        let id: Int
        let state: SleepState
        let start: Date
        let end: Date
    }

    private var segments: [Segment] {
        let phases = night.phases.sorted { $0.secondsFromStart < $1.secondsFromStart }
        return phases.enumerated().map { index, phase in
            let end = index + 1 < phases.count ? night.start.addingTimeInterval(TimeInterval(phases[index + 1].secondsFromStart)) : night.end
            return Segment(id: index, state: phase.state, start: night.start.addingTimeInterval(TimeInterval(phase.secondsFromStart)), end: end)
        }
    }

    /// Polar's "unknown" gets a row only on a night that has it. Top to bottom.
    static func stages(of night: SleepNight) -> [SleepState] {
        let base: [SleepState] = [.wake, .rem, .light, .deep]
        return night.phases.contains { $0.state == .unknown } ? base + [.unknown] : base
    }

    static func label(_ state: SleepState) -> String {
        switch state {
        case .wake: "Awake"
        case .rem: "REM"
        case .light: "Light"
        case .deep: "Deep"
        case .unknown: "Unknown"
        }
    }

    static func color(_ state: SleepState) -> Color {
        switch state {
        case .wake: Theme.Palette.stress
        case .rem: Theme.Palette.accent
        case .light: Theme.Palette.sleep.opacity(0.55)
        case .deep: Theme.Palette.sleep
        case .unknown: Theme.Palette.mutedText
        }
    }

    var body: some View {
        if compact {
            chart
                .chartXAxis(.hidden)
                .frame(height: 44)
        } else {
            chart
                .chartScrub($selection, style: scrub)
                .chartXAxis {
                    AxisMarks(values: marks) { _ in AxisGridLine() }
                }
                .frame(height: typeSize.isAccessibilitySize ? 270 : 180)
        }
    }

    private var chart: some View {
        Chart {
            ForEach(segments) { segment in
                BarMark(
                    xStart: .value("From", segment.start), xEnd: .value("To", segment.end),
                    y: .value("Stage", Self.label(segment.state))
                )
                .foregroundStyle(Self.color(segment.state))
                .cornerRadius(3)
            }
            if let selection {
                ScrubRule(date: selection)
                if let state = night.state(at: selection) {
                    ScrubDot(date: selection, value: Self.label(state), color: Theme.Palette.text)
                }
            }
        }
        .chartYScale(domain: Self.stages(of: night).map(Self.label))
        .chartXScale(domain: night.start...night.end)
        .chartYAxis(.hidden)
    }
}
