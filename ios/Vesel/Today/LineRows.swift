import SwiftUI
import VeselCore
import VeselStorage

/// Recovery, Sleep and Calm as three range lines on one glass card. Each row opens its own page. A line still learning its normal shows
/// its first-week row of checks instead. With no `night`, Recovery and Sleep say it is processing or show a dash.
struct LineRows: View {
    let night: NightReport?
    let nightPending: Bool
    let dayLines: DayLines?
    let firstWeek: FirstWeek?
    let zone: TimeZone
    let calmText: String
    let openRecovery: () -> Void
    let openSleep: () -> Void
    let openCalm: () -> Void

    var body: some View {
        GlassCard { rows }
    }

    private var noNight: String { nightPending ? "Evaluating…" : "—" }

    private var rows: some View {
        VStack(spacing: Theme.Spacing.s8) {
            if let row = firstWeek?.row(.recovery) {
                FirstWeekRow(title: "Recovery", row: row, color: Theme.Palette.recovery, zone: zone, action: openRecovery)
            } else {
                LineRow(
                    title: "Recovery", value: night.map { $0.status?.word.capitalizedFirst ?? "—" } ?? noNight,
                    verdict: night.flatMap { _ in dayLines?.recovery },
                    color: Theme.Palette.recoveryLine(night?.status), action: openRecovery, hint: "Opens Recovery"
                )
            }
            if let row = firstWeek?.row(.sleep) {
                FirstWeekRow(title: "Sleep", row: row, color: Theme.Palette.sleep, zone: zone, action: openSleep)
            } else {
                LineRow(
                    title: "Sleep", value: night.map { $0.value(MetricKind.sleepAsleep).map { DurationText.hoursMinutes(minutes: $0) } ?? "—" } ?? noNight,
                    verdict: night.flatMap { _ in dayLines?.sleep }, color: Theme.Palette.sleep, action: openSleep, hint: "Opens Sleep"
                )
            }
            if let row = firstWeek?.row(.calm) {
                FirstWeekRow(title: "Stress", row: row, color: Theme.Palette.stress, zone: zone, action: openCalm)
            } else {
                LineRow(title: "Stress", value: calmText, verdict: dayLines?.calm, color: Theme.Palette.stress, action: openCalm, hint: "Opens Stress")
            }
            if firstWeek != nil {
                Text("A night the Loop missed leaves its check empty and the row one longer.")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private extension FirstWeek {
    func row(_ line: FirstWeek.Line) -> Row? { rows.first { $0.line == line } }
}

/// One range line with its name and value. A button on Today (it has an action); a plain row on its own page.
struct LineRow: View {
    let title: String
    let value: String
    let verdict: LineVerdict?
    let color: Color
    var action: (() -> Void)?
    var hint = ""
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
                .modifier(Speech(title: title, spoken: spoken, hint: hint))
        } else {
            content.modifier(Speech(title: title, spoken: spoken, hint: ""))
        }
    }

    private var state: LineState { verdict?.state ?? .none }
    private var spoken: String { state.spokenValue(value) }

    private var content: some View {
        let names =
            typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.s4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        return VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
            names {
                Text(title)
                    .font(Theme.Typography.heading)
                    .foregroundStyle(Theme.Palette.mutedText)
                if !typeSize.isAccessibilitySize { Spacer(minLength: Theme.Spacing.s8) }
                Text(value)
                    .font(Theme.Typography.heading)
                    .foregroundStyle(Theme.Palette.text)
            }
            if !state.isLearning {
                RangeLine(scale: verdict?.scale, outside: state.isOutside, color: color)
            }
        }
        .padding(.vertical, Theme.Spacing.s8)
        .frame(maxWidth: .infinity, minHeight: Theme.Size.tapTarget, alignment: .leading)
        .contentShape(.rect)
    }

    private struct Speech: ViewModifier {
        let title: String
        let spoken: String
        let hint: String

        func body(content: Content) -> some View {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityValue(spoken)
                .accessibilityHint(hint)
        }
    }
}
