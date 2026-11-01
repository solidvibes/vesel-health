import SwiftUI
import VeselCore

/// The range line bent into a 270 degree arc open at the bottom, for the round Lock Screen spot. The same parts as
/// `RangeLine`: a track, your normal shaded, a dot (filled inside, hollow outside); `content` sits in the middle.
struct RangeArc<Content: View>: View {
    let scale: LineScale?
    let outside: Bool
    let color: Color
    let lineWidth: CGFloat
    @ViewBuilder var content: Content

    private var sweep: Double { 0.75 }
    private var startDegrees: Double { 135 }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let dotSize = lineWidth * 1.7
            let radius = (side - dotSize) / 2
            ZStack {
                arc(from: 0, to: 1)
                    .stroke(Theme.Palette.mutedText.opacity(0.22), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                if let scale {
                    arc(from: scale.normalFrom, to: scale.normalTo)
                        .stroke(color.opacity(0.35), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                        .widgetAccentable()
                    dot(size: dotSize)
                        .offset(position(scale.dot, radius: radius))
                        .widgetAccentable()
                }
                content
            }
            .frame(width: side, height: side)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    private func arc(from: Double, to: Double) -> some Shape {
        Circle()
            .inset(by: lineWidth * 0.85)
            .trim(from: from * sweep, to: to * sweep)
            .rotation(.degrees(startDegrees))
    }

    private func position(_ fraction: Double, radius: CGFloat) -> CGSize {
        let angle = Angle.degrees(startDegrees + fraction * sweep * 360).radians
        return CGSize(width: radius * cos(angle), height: radius * sin(angle))
    }

    @ViewBuilder private func dot(size: CGFloat) -> some View {
        if outside {
            Circle()
                .fill(Theme.Palette.surface)
                .overlay(Circle().strokeBorder(color, lineWidth: lineWidth * 0.45))
                .frame(width: size, height: size)
        } else {
            Circle()
                .fill(color)
                .overlay(Circle().strokeBorder(Theme.Palette.surface, lineWidth: lineWidth * 0.25))
                .frame(width: size, height: size)
        }
    }
}
