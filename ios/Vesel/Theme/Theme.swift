import SwiftUI
import VeselCore

/// The look from `docs/design/system.md`.
enum Theme {
    enum Palette {
        static let background = Color("Background")
        static let surface = Color("Surface")
        static let text = Color("Text")
        static let mutedText = Color("MutedText")
        static let primary = Color("Primary")
        static let onPrimary = Color("OnPrimary")
        static let accent = Color("Accent")
        static let onAccent = Color("OnAccent")
        static let error = Color("Error")
        static let onError = Color("OnError")
        static let success = Color("Success")
        static let recovery = Color("Recovery")
        static let sleep = Color("Sleep")
        static let stress = Color("Stress")
        /// Workout blocks, lines and the route. Never the only sign: blocks have a top edge and the sport in words.
        static let workout = Color("Workout")

        /// A mark's chip is also the chart dot colour; its ink is the symbol on the chip.
        static func markChip(_ mark: NormalMark) -> Color {
            switch mark {
            case .inside: Color("MarkInside")
            case .better: Color("MarkBetter")
            case .off: Color("MarkOff")
            case .far: Color("MarkFar")
            }
        }

        static func markInk(_ mark: NormalMark) -> Color {
            switch mark {
            case .inside: Color("OnMarkInside")
            case .better: Color("OnMarkBetter")
            case .off: Color("OnMarkOff")
            case .far: Color("OnMarkFar")
            }
        }

        /// The Recovery line follows Polar's verdict: the warm colour (the one "something's off" uses) when it is
        /// compromised or worse, the recovery green otherwise.
        static func recoveryLine(_ status: RecoveryStatus?) -> Color {
            recoveryLine(indicator: status?.indicator)
        }

        static func recoveryLine(indicator: Int?) -> Color {
            indicator.map(RecoveryStatus.isLow) == true ? stress : recovery
        }
    }

    enum Spacing {
        static let s4: CGFloat = 4
        static let s8: CGFloat = 8
        static let s12: CGFloat = 12
        static let s16: CGFloat = 16
        static let s20: CGFloat = 20
        static let s24: CGFloat = 24
        static let s32: CGFloat = 32
        static let s40: CGFloat = 40
        static let s48: CGFloat = 48
        static let edge: CGFloat = 20
    }

    enum Corner {
        static let small: CGFloat = 12
        static let card: CGFloat = 24
        static let sheet: CGFloat = 32
    }

    enum Size {
        static let tapTarget: CGFloat = 48
        static let row: CGFloat = 52
    }

    enum Typography {
        static let display = Font.largeTitle.bold()
        static let title = Font.title.bold()
        static let heading = Font.title3.weight(.semibold)
        static let body = Font.body
        static let label = Font.subheadline.weight(.semibold)
        static let small = Font.footnote.weight(.medium)
    }
}
