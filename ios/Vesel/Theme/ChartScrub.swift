import Charts
import SwiftUI
import UIKit

/// One scrub for every chart that has one: a finger moves a vertical line and the page's header reads the stored values at that
/// moment; lifting the finger clears it. VoiceOver gets the same through an adjustable action.
/// How a finger scrubs a chart. Glances scrub at once; a page's charts need a short hold first, so a sideways drag pages the whole
/// page and a tap can pick a day.
enum ChartScrubStyle {
    case immediate
    /// `slot` names the bar, hour or point a moment falls on: the scrub ticks each time it moves to another one.
    case holdThenDrag(slot: (Date) -> Int, onTap: ((Date) -> Void)? = nil)
}

extension View {
    /// The finger, per chart. Lifting it sets the selection back to nil.
    @ViewBuilder func chartScrub(_ selection: Binding<Date?>, style: ChartScrubStyle = .immediate) -> some View {
        switch style {
        case .immediate:
            chartXSelection(value: selection)
        case .holdThenDrag(let slot, let onTap):
            modifier(PeriodChartGestures(selection: selection, slot: slot, onTap: onTap))
        }
    }

    /// Once per card, on the container that holds the label and the chart(s): one element that swipes up or down
    /// through `domain` in steps, and reads `value`.
    func scrubAccessibility(_ selection: Binding<Date?>, domain: ClosedRange<Date>, step: TimeInterval = 15 * 60, label: String, value: String) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(value)
            .accessibilityAdjustableAction { direction in
                let current = selection.wrappedValue ?? domain.lowerBound.addingTimeInterval(direction == .increment ? -step : step)
                switch direction {
                case .increment: selection.wrappedValue = min(current.addingTimeInterval(step), domain.upperBound)
                case .decrement: selection.wrappedValue = max(current.addingTimeInterval(-step), domain.lowerBound)
                @unknown default: break
                }
            }
    }
}

/// The vertical line at the finger.
struct ScrubRule: ChartContent {
    let date: Date

    var body: some ChartContent {
        RuleMark(x: .value("Selected", date))
            .foregroundStyle(Theme.Palette.text)
            .lineStyle(StrokeStyle(lineWidth: 1))
    }
}

/// The dot where the scrub line meets the plotted value: the series' colour with a ring in the background colour.
struct ScrubDot<Y: Plottable>: ChartContent {
    let date: Date
    let value: Y
    let color: Color

    var body: some ChartContent {
        PointMark(x: .value("Selected", date), y: .value("Value", value))
            .symbolSize(150)
            .foregroundStyle(Theme.Palette.background)
            .accessibilityHidden(true)
        PointMark(x: .value("Selected", date), y: .value("Value", value))
            .symbolSize(60)
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}

/// `-VeselScrub 03:12`, Simulator only: where the first scrubbable chart shown starts out selected.
struct ScrubTime: Equatable {
    let hour: Int
    let minute: Int

    init?(_ text: String) {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        hour = parts[0]
        minute = parts[1]
    }

    /// The first moment inside `domain` at this clock time in `zone`; nil when the domain has none.
    func moment(in domain: ClosedRange<Date>, zone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let first = calendar.startOfDay(for: domain.lowerBound)
        return (0...2).compactMap { offset -> Date? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: first) else { return nil }
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
        }.first { domain.contains($0) }
    }
}

/// Keeps a chart's hold-to-scrub ahead of the system's swipe back (a pan outside any scroll view) and out of the page's scrolls: the
/// hold fails as soon as the finger moves before it is over, and once it holds no scroll takes the finger.
private final class HoldDelegate: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        !(other is UIPanGestureRecognizer)
    }

    /// The swipe back waits for this chart to let go.
    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        other is UIPanGestureRecognizer && !(other.view is UIScrollView)
    }
}

/// Hold about a quarter of a second, then drag: reports where the finger is (in the chart's own space) while it moves, and nil when it
/// lifts or the system takes the touch. A finger that moves before the hold is over fails it, so the page scrolls instead.
private struct HoldToScrub: UIGestureRecognizerRepresentable {
    let onMove: (CGFloat?) -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let press = UILongPressGestureRecognizer()
        press.minimumPressDuration = 0.25
        press.delegate = context.coordinator
        return press
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed: onMove(context.converter.localLocation.x)
        default: onMove(nil)
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> HoldDelegate { HoldDelegate() }
}

/// Hold about a quarter of a second, then drag: the selection follows the finger and lifting clears it. A tap (`onTap` with the moment
/// tapped) is told apart from it. The hold is a UIKit recognizer, so the page still scrolls and pages from the chart and the system's
/// swipe back still works off it.
private struct PeriodChartGestures: ViewModifier {
    @Binding var selection: Date?
    let slot: (Date) -> Int
    let onTap: ((Date) -> Void)?
    @State private var scrubbing = false

    func body(content: Content) -> some View {
        content
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Color.clear
                        .contentShape(.rect)
                        .gesture(
                            HoldToScrub { x in
                                if let x {
                                    scrubbing = true
                                    selection = moment(at: x, proxy: proxy, geometry: geometry)
                                } else {
                                    selection = nil
                                    Task { scrubbing = false }
                                }
                            }
                        )
                        .simultaneousGesture(
                            SpatialTapGesture().onEnded { tap in
                                guard !scrubbing, let moment = moment(at: tap.location.x, proxy: proxy, geometry: geometry) else { return }
                                onTap?(moment)
                            }
                        )
                }
            }
            .sensoryFeedback(trigger: selection.map(slot)) { _, new in scrubbing && new != nil ? .selection : nil }
    }

    private func moment(at x: CGFloat, proxy: ChartProxy, geometry: GeometryProxy) -> Date? {
        guard let plot = proxy.plotFrame else { return nil }
        let frame = geometry[plot]
        let inside = min(max(x - frame.minX, 0), frame.width)
        return proxy.value(atX: inside, as: Date.self)
    }
}
