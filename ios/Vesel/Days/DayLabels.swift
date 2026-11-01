import SwiftUI
import VeselCore
import VeselStorage

/// What VoiceOver says for a day in the month calendar and in the week strip, and the dots drawn for it.
enum DayLabels {
    static func spoken(_ day: DayKey, lines: DayLines?, pickable: Bool, zone: TimeZone) -> String {
        let date = day.start(in: zone).formatted(Date.FormatStyle(timeZone: zone).weekday(.wide).day().month(.wide))
        guard pickable else { return "\(date). No data" }
        let lines = lines ?? .empty
        return "\(date), recovery \(word(lines.recovery.state)), sleep \(word(lines.sleep.state)), stress \(word(lines.calm.state))"
    }

    private static func word(_ state: LineState) -> String {
        switch state {
        case .none: "no data"
        case .learning: "learning"
        case .inside: "inside your normal"
        case .below: "below your normal"
        case .above: "above your normal"
        }
    }
}

extension DayDots {
    init(_ lines: DayLines) {
        self.init(
            recovery: DotState(lines.recovery.state),
            sleep: DotState(lines.sleep.state),
            calm: DotState(lines.calm.state),
            recoveryColor: Theme.Palette.recoveryLine(indicator: lines.indicator)
        )
    }
}

extension View {
    /// The glass tile with an outline in the accent colour behind the picked day.
    func pickedDayHighlight(_ picked: Bool) -> some View {
        background {
            if picked {
                RoundedRectangle(cornerRadius: Theme.Corner.small)
                    .fill(.clear)
                    .glassEffect(.regular, in: .rect(cornerRadius: Theme.Corner.small))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Corner.small).stroke(Theme.Palette.primary, lineWidth: 1.5))
            }
        }
    }
}
