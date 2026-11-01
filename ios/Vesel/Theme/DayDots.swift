import SwiftUI
import VeselCore

/// How one day's dot is drawn.
enum DotState: Equatable {
    case inside, outside, learning, none

    init(_ state: LineState) {
        switch state {
        case .inside: self = .inside
        case .below, .above: self = .outside
        case .learning: self = .learning
        case .none: self = .none
        }
    }
}

/// A day in three 6 pt dots side by side: recovery, sleep, calm. Filled inside your normal, hollow outside it, a small
/// muted dot while learning, an empty slot with no data. A nil dot is an empty slot too.
struct DayDots: View {
    let recovery: DotState?
    let sleep: DotState?
    let calm: DotState?
    let recoveryColor: Color

    var body: some View {
        HStack(spacing: 3) {
            DotMark(state: recovery, color: recoveryColor)
            DotMark(state: sleep, color: Theme.Palette.sleep)
            DotMark(state: calm, color: Theme.Palette.stress)
        }
        .accessibilityHidden(true)
    }
}

/// One 6 pt dot: filled inside your normal, hollow outside it, small and muted while learning, empty with no data.
struct DotMark: View {
    let state: DotState?
    let color: Color

    var body: some View {
        Group {
            switch state {
            case .inside:
                Circle().fill(color)
            case .outside:
                Circle().strokeBorder(color, lineWidth: 1.5)
            case .learning:
                Circle().fill(Theme.Palette.mutedText.opacity(0.5)).padding(1)
            case .some(.none), nil:
                Color.clear
            }
        }
        .frame(width: 6, height: 6)
    }
}
