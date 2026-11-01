import SwiftUI
import VeselCore

/// A day's line: a track, your normal shaded on it and a dot for the day, drawn from a `LineScale`. The dot is filled
/// inside your normal and hollow outside it. No scale is the track alone. The shaded normal and the dot are marked
/// accentable so the Lock Screen's tinted mode picks them out. Hidden from VoiceOver: the row speaks.
struct RangeLine: View {
    let scale: LineScale?
    let outside: Bool
    let color: Color
    /// The track's thickness; the dot is 1.4 times it (14 pt on the 10 pt track).
    var height: CGFloat = 10

    private var dotSize: CGFloat { height * 1.4 }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.Palette.mutedText.opacity(0.22))
                    .frame(height: height)
                if let scale {
                    Capsule()
                        .fill(color.opacity(0.35))
                        .frame(width: max(width * (scale.normalTo - scale.normalFrom), height), height: height)
                        .offset(x: width * scale.normalFrom)
                        .widgetAccentable()
                    dot
                        .offset(x: scale.dot * (width - dotSize))
                        .widgetAccentable()
                }
            }
            .frame(height: dotSize)
        }
        .frame(height: dotSize)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var dot: some View {
        if outside {
            Circle()
                .fill(Theme.Palette.surface)
                .overlay(Circle().strokeBorder(color, lineWidth: height * 0.3))
                .frame(width: dotSize, height: dotSize)
        } else {
            Circle()
                .fill(color)
                .overlay(Circle().strokeBorder(Theme.Palette.surface, lineWidth: height * 0.2))
                .frame(width: dotSize, height: dotSize)
        }
    }
}

extension LineState {
    var isLearning: Bool {
        if case .learning = self { true } else { false }
    }

    /// What VoiceOver adds to a line's value; nil with no data.
    var spoken: String? {
        switch self {
        case .none: nil
        case .learning: "learning your normal"
        case .inside: "inside your normal"
        case .below: "below your normal"
        case .above: "above your normal"
        }
    }

    /// The line's state as a row's value: "Inside your normal".
    var rowWord: String {
        switch self {
        case .none: "No data"
        case .learning: "Learning"
        case .inside: "Inside your normal"
        case .below: "Below your normal"
        case .above: "Above your normal"
        }
    }

    /// "Strong, inside your normal"; the value alone with no data.
    func spokenValue(_ value: String) -> String {
        spoken.map { "\(value), \($0)" } ?? value
    }
}

#if DEBUG
#Preview {
    VStack(spacing: Theme.Spacing.s24) {
        RangeLine(scale: LineScale(normalFrom: 0.3, normalTo: 0.7, dot: 0.5, value: 50), outside: false, color: Theme.Palette.recovery)
        RangeLine(scale: LineScale(normalFrom: 0.3, normalTo: 0.7, dot: 0.9, value: 90), outside: true, color: Theme.Palette.stress)
        RangeLine(scale: nil, outside: false, color: Theme.Palette.sleep)
    }
    .padding(Theme.Spacing.edge)
    .background { BlobBackground() }
}
#endif
