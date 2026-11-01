import SwiftUI

/// One faint wash of the data colours at the top right behind the glass: mostly sleep blue, a fainter touch of recovery green over it.
/// `warm` adds a quiet stress-coloured glow at the top for Today's "something's off".
struct BlobBackground: View {
    var warm = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Theme.Palette.background
                blob(Theme.Palette.sleep, diameter: size.width * 1.0, opacity: 0.10)
                    .offset(x: size.width * 0.25, y: -size.height * 0.45)
                blob(Theme.Palette.recovery, diameter: size.width * 0.7, opacity: 0.07)
                    .offset(x: size.width * 0.05, y: -size.height * 0.4)
                if warm {
                    blob(Theme.Palette.stress, diameter: size.width * 1.1, opacity: 0.18)
                        .offset(x: size.width * 0.25, y: -size.height * 0.32)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func blob(_ color: Color, diameter: CGFloat, opacity: Double) -> some View {
        Circle()
            .fill(color.opacity(opacity))
            .frame(width: diameter, height: diameter)
            .blur(radius: diameter / 3)
    }
}

/// The home-screen widgets' background: the wash, with a surface-coloured layer over them so labels and values keep their contrast.
struct WidgetBackground: View {
    var body: some View {
        BlobBackground()
            .overlay(Theme.Palette.surface.opacity(0.78).ignoresSafeArea())
    }
}
