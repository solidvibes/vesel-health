import Foundation
import Observation
import SwiftUI
import VeselCore
import VeselStorage

/// The seven days of one page under Journal's title, and the three dots each carries.
@MainActor
@Observable
final class WeekStripModel {
    private(set) var weekStart: DayKey
    private var loaded: (week: DayKey, lines: [DayKey: DayLines])?
    private let database: AppDatabase
    private let clock: any VeselClock
    private let selection: DaySelection
    @ObservationIgnored private let calendar: Calendar

    init(database: AppDatabase, clock: any VeselClock, days: DaySelection) {
        self.database = database
        self.clock = clock
        selection = days
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = clock.timeZone
        self.calendar = calendar
        weekStart = DayKey(year: 2000, month: 1, day: 1)
        weekStart = page(holding: days.day)
    }

    var zone: TimeZone { clock.timeZone }
    var today: DayKey { clock.today }
    var picked: DayKey { selection.day }

    var days: [DayKey] { (0..<7).map { weekStart.adding(days: $0) } }

    var canGoEarlier: Bool { weekStart > page(holding: selection.firstDay ?? today) }
    var canGoLater: Bool { weekStart < page(holding: today) }

    func earlier() { if canGoEarlier { weekStart = weekStart.adding(days: -7) } }
    func later() { if canGoLater { weekStart = weekStart.adding(days: 7) } }

    /// Back to the page holding the picked day, after the day or today changed.
    func follow() { weekStart = page(holding: picked) }

    /// The Monday of the week holding a day. A page is one week, Monday to Sunday; days after today show but can't be picked.
    func page(holding day: DayKey) -> DayKey {
        let weekday = calendar.component(.weekday, from: day.start(in: zone))
        return day.adding(days: -((weekday + 5) % 7))
    }

    /// "M", "T"… for a day.
    func letter(_ day: DayKey) -> String {
        calendar.veryShortStandaloneWeekdaySymbols[calendar.component(.weekday, from: day.start(in: zone)) - 1]
    }

    func lines(_ day: DayKey) -> DayLines? {
        loaded.flatMap { $0.week == weekStart ? $0.lines[day] : nil }
    }

    func canPick(_ day: DayKey) -> Bool { selection.canSelect(day) }

    func pick(_ day: DayKey) { selection.select(day) }

    func observe() async {
        let shown = weekStart
        do {
            for try await value in database.observeDayLines(from: shown, through: shown.adding(days: 6)) {
                loaded = (shown, value)
            }
        } catch {
            // Keeps what it last read; it starts again when Vesel comes to the front.
        }
    }
}

/// A week of days with their three dots. Tap a day to pick it; swipe to move a week.
struct WeekStrip: View {
    @State private var model: WeekStripModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(environment: AppEnvironment) {
        _model = State(initialValue: WeekStripModel(database: environment.database, clock: environment.clock, days: environment.days))
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.s4) {
            ForEach(model.days, id: \.self) { day in cell(day) }
        }
        .id(model.weekStart)
        .transition(.opacity)
        .simultaneousGesture(
            DragGesture(minimumDistance: 24).onEnded { drag in
                guard abs(drag.translation.width) > abs(drag.translation.height) * 1.5 else { return }
                page(drag.translation.width < 0 ? .later : .earlier)
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Week of \(Formatters.day(model.weekStart, zone: model.zone))")
        .accessibilityScrollAction { edge in
            switch edge {
            case .leading: page(.earlier)
            case .trailing: page(.later)
            default: break
            }
        }
        .onChange(of: model.picked) { model.follow() }
        .task(id: ObserveKey(value: model.weekStart, active: scenePhase == .active)) {
            guard scenePhase == .active else { return }
            await model.observe()
        }
    }

    private enum Direction { case earlier, later }

    private func page(_ direction: Direction) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            if direction == .earlier { model.earlier() } else { model.later() }
        }
    }

    private func cell(_ day: DayKey) -> some View {
        let pickable = model.canPick(day)
        let picked = day == model.picked
        return Button {
            model.pick(day)
        } label: {
            VStack(spacing: Theme.Spacing.s4) {
                if !typeSize.isAccessibilitySize {
                    Text(model.letter(day))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.Palette.mutedText)
                }
                Text(String(day.day))
                    .font(.footnote.weight(picked ? .bold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if pickable {
                    DayDots(model.lines(day) ?? .empty)
                } else {
                    Color.clear.frame(width: 24, height: 6)
                }
            }
            .foregroundStyle(Theme.Palette.text)
            .opacity(pickable ? 1 : 0.35)
            .frame(maxWidth: .infinity, minHeight: 72)
            .pickedDayHighlight(picked)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!pickable)
        .accessibilityLabel(DayLabels.spoken(day, lines: model.lines(day), pickable: pickable, zone: model.zone))
        .accessibilityAddTraits(picked ? .isSelected : [])
        .accessibilityActions {
            if model.canGoEarlier { Button("Earlier week") { page(.earlier) } }
            if model.canGoLater { Button("Later week") { page(.later) } }
        }
    }
}
