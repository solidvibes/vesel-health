import Foundation
import Observation
import SwiftUI
import VeselCore
import VeselStorage

/// One month of the calendar: its days and each day's dots.
@MainActor
@Observable
final class CalendarMonthModel {
    private(set) var month: DayKey
    private var loaded: (month: DayKey, lines: [DayKey: DayLines])?
    private let database: AppDatabase
    private let clock: any VeselClock
    private let selection: DaySelection
    @ObservationIgnored private let calendar: Calendar

    init(database: AppDatabase, clock: any VeselClock, days: DaySelection) {
        self.database = database
        self.clock = clock
        selection = days
        let day = days.day
        month = DayKey(year: day.year, month: day.month, day: 1)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = clock.timeZone
        calendar.firstWeekday = Calendar.current.firstWeekday
        self.calendar = calendar
    }

    var zone: TimeZone { clock.timeZone }
    var today: DayKey { clock.today }
    var picked: DayKey { selection.day }

    private var currentMonth: DayKey { DayKey(year: today.year, month: today.month, day: 1) }
    private var firstMonth: DayKey { selection.firstDay.map { DayKey(year: $0.year, month: $0.month, day: 1) } ?? currentMonth }

    var canGoEarlier: Bool { month > firstMonth }
    var canGoLater: Bool { month < currentMonth }

    func earlier() { month = month.adding(days: -1).firstOfMonth }
    func later() { month = month.adding(days: dayCount).firstOfMonth }

    private var dayCount: Int { calendar.range(of: .day, in: .month, for: month.start(in: zone))?.count ?? 30 }

    var title: String {
        month.start(in: zone).formatted(Date.FormatStyle(timeZone: zone).month(.wide).year())
    }

    /// The month's days up to today.
    var days: [DayKey] {
        (0..<dayCount).map { month.adding(days: $0) }.filter { $0 <= today }
    }

    /// The month's days with blanks before the first, so a row of seven starts on the phone's first weekday.
    var gridCells: [DayKey?] {
        let weekday = calendar.component(.weekday, from: month.start(in: zone))
        let blanks = (weekday - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: blanks) + (0..<dayCount).map { month.adding(days: $0) }
    }

    /// "M", "T"… from the phone's first weekday.
    var weekdayHeaders: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
    }

    func lines(_ day: DayKey) -> DayLines? {
        loaded.flatMap { $0.month == month ? $0.lines[day] : nil }
    }

    func canPick(_ day: DayKey) -> Bool { selection.canSelect(day) }

    func pick(_ day: DayKey) { selection.select(day) }

    func observe() async {
        let shown = month
        let last = min(shown.adding(days: dayCount - 1), today)
        guard shown <= last else { return }
        do {
            for try await value in database.observeDayLines(from: shown, through: last) {
                loaded = (shown, value)
            }
        } catch {
            // Keeps what it last read; it starts again when Vesel comes to the front.
        }
    }
}

private extension DayKey {
    var firstOfMonth: DayKey { DayKey(year: year, month: month, day: 1) }
}

/// The month calendar Journal's title opens: every day with its three dots; tap one to see it.
struct DayCalendar: View {
    @State private var model: CalendarMonthModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase

    init(environment: AppEnvironment) {
        _model = State(initialValue: CalendarMonthModel(database: environment.database, clock: environment.clock, days: environment.days))
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.s12) {
            header
            ScrollView {
                if typeSize.isAccessibilitySize {
                    list
                } else {
                    grid
                }
            }
            Button("Today") {
                model.pick(model.today)
                dismiss()
            }
            .buttonStyle(.veselSecondary)
        }
        .padding(.horizontal, Theme.Spacing.edge)
        .padding(.top, Theme.Spacing.s24)
        .padding(.bottom, Theme.Spacing.s16)
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(fittedHeight), .large])
        .presentationBackground(Theme.Palette.background)
        .task(id: ObserveKey(value: model.month, active: scenePhase == .active)) {
            guard scenePhase == .active else { return }
            await model.observe()
        }
    }

    /// Tall enough for the header, every week row and the button, so nothing hides behind it; the sheet caps it at the screen.
    private var fittedHeight: CGFloat {
        let rows = CGFloat((model.gridCells.count + 6) / 7)
        let grid = 20 + rows * (Theme.Size.row + Theme.Spacing.s4)
        let chrome = Theme.Spacing.s24 + Theme.Size.tapTarget + Theme.Spacing.s12 * 2 + Theme.Size.tapTarget + Theme.Spacing.s16
        return chrome + grid
    }

    private var header: some View {
        HStack {
            monthButton("chevron.left", label: "Earlier month", enabled: model.canGoEarlier, action: model.earlier)
            Spacer()
            Text(model.title)
                .font(Theme.Typography.heading)
                .foregroundStyle(Theme.Palette.text)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            monthButton("chevron.right", label: "Later month", enabled: model.canGoLater, action: model.later)
        }
    }

    private func monthButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Palette.text)
                .frame(width: Theme.Size.tapTarget, height: Theme.Size.tapTarget)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(label)
    }

    private var grid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.s4), count: 7)
        return LazyVGrid(columns: columns, spacing: Theme.Spacing.s4) {
            ForEach(Array(model.weekdayHeaders.enumerated()), id: \.offset) { _, letter in
                Text(letter)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.Palette.mutedText)
                    .accessibilityHidden(true)
            }
            ForEach(Array(model.gridCells.enumerated()), id: \.offset) { _, cell in
                if let day = cell {
                    dayButton(day) { gridCell(day) }
                } else {
                    Color.clear.frame(height: 1)
                }
            }
        }
    }

    private func gridCell(_ day: DayKey) -> some View {
        VStack(spacing: 1) {
            Text(String(day.day))
                .font(.footnote.weight(isPicked(day) ? .bold : .regular))
            dots(day)
        }
        .frame(maxWidth: .infinity, minHeight: Theme.Size.row)
    }

    private var list: some View {
        LazyVStack(spacing: Theme.Spacing.s4) {
            ForEach(model.days, id: \.self) { day in
                dayButton(day) {
                    HStack {
                        Text(Formatters.day(day, zone: model.zone))
                            .font(Theme.Typography.body.weight(isPicked(day) ? .bold : .regular))
                        Spacer()
                        dots(day)
                    }
                    .padding(.horizontal, Theme.Spacing.s16)
                    .frame(maxWidth: .infinity, minHeight: Theme.Size.row)
                }
            }
        }
    }

    private func isPicked(_ day: DayKey) -> Bool { day == model.picked }

    private func dayButton<Label: View>(_ day: DayKey, @ViewBuilder label: () -> Label) -> some View {
        let pickable = model.canPick(day)
        let picked = isPicked(day)
        return Button {
            model.pick(day)
            dismiss()
        } label: {
            label()
                .foregroundStyle(Theme.Palette.text)
                .opacity(pickable ? 1 : 0.35)
                .pickedDayHighlight(picked)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!pickable)
        .accessibilityLabel(DayLabels.spoken(day, lines: model.lines(day), pickable: pickable, zone: model.zone))
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    @ViewBuilder private func dots(_ day: DayKey) -> some View {
        if model.canPick(day) {
            DayDots(model.lines(day) ?? .empty)
        } else {
            Color.clear.frame(width: 24, height: 6)
        }
    }
}

/// The ink pill that takes a past day back to today.
struct BackToTodayPill: View {
    let environment: AppEnvironment

    var body: some View {
        Button("Back to today") { environment.days.select(environment.clock.today) }
            .font(Theme.Typography.label)
            .foregroundStyle(Theme.Palette.onPrimary)
            .padding(.horizontal, Theme.Spacing.s16)
            .frame(minHeight: Theme.Size.tapTarget)
            .background(Theme.Palette.primary, in: .capsule)
            .contentShape(.capsule)
            .buttonStyle(.plain)
    }
}
