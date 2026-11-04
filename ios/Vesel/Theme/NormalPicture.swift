import SwiftUI
import VeselCore

/// Where one reading sits against your normal: a track, your normal shaded on it with its ends written under, and the reading as a dot
/// filled in its mark's colour with its value and `MarkBadge` over it; without a mark (In bed) it takes `color` and has no badge. One element for VoiceOver, which reads `spoken`.
struct NormalPicture: View {
    let scale: LineScale
    let mark: NormalMark?
    let color: Color
    let value: String
    let low: String
    let high: String
    let spoken: String
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .footnote) private var rowHeight: CGFloat = 28
    @ScaledMetric(relativeTo: .footnote) private var track: CGFloat = 12

    private var dotSize: CGFloat { track * 1.6 }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
            GeometryReader { proxy in
                HStack(spacing: Theme.Spacing.s8) {
                    if let mark { MarkBadge(mark: mark) }
                    Text(value)
                        .font(Theme.Typography.label.monospacedDigit())
                        .foregroundStyle(Theme.Palette.text)
                        .fixedSize()
                }
                .centered(at: x(scale.dot, in: proxy.size.width), in: proxy.size.width)
            }
            .frame(height: rowHeight)
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.Palette.mutedText.opacity(0.22))
                        .frame(height: track)
                    Capsule()
                        .fill(color.opacity(0.35))
                        .frame(width: max(x(scale.normalTo, in: width) - x(scale.normalFrom, in: width), track), height: track)
                        .offset(x: x(scale.normalFrom, in: width))
                    Circle()
                        .fill(mark.map(Theme.Palette.markChip) ?? color)
                        .overlay(Circle().strokeBorder(Theme.Palette.surface, lineWidth: 2))
                        .frame(width: dotSize, height: dotSize)
                        .offset(x: scale.dot * (width - dotSize))
                }
                .frame(height: dotSize)
            }
            .frame(height: dotSize)
            if typeSize.isAccessibilitySize {
                Text("Your normal \(low) to \(high)")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        end(low).centered(at: x(scale.normalFrom, in: proxy.size.width), in: proxy.size.width)
                        end(high).centered(at: x(scale.normalTo, in: proxy.size.width), in: proxy.size.width)
                    }
                }
                .frame(height: rowHeight)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// Where a point `fraction` along the track sits, on the same scale as the dot's middle, so a dot on the normal's edge sits on the band's edge.
    private func x(_ fraction: Double, in width: CGFloat) -> CGFloat { dotSize / 2 + fraction * (width - dotSize) }

    private func end(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.small.monospacedDigit())
            .foregroundStyle(Theme.Palette.mutedText)
            .fixedSize()
    }
}

extension View {
    /// Puts the view's middle `x` points from the container's left edge, kept inside the container's `width`.
    fileprivate func centered(at x: CGFloat, in width: CGFloat) -> some View {
        alignmentGuide(.leading) { dimensions in max(min(dimensions.width / 2 - x, 0), dimensions.width - width) }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
private struct NormalPictureSheet: View {
    let cases: [(NormalMark?, LineScale, String)] = [
        (nil, LineScale(normalFrom: 0.33, normalTo: 0.66, dot: 0.6, value: 470), "7 h 50 m"),
        (.inside, LineScale(normalFrom: 0.33, normalTo: 0.66, dot: 0.5, value: 44), "44 ms"),
        (.better(.above), LineScale(normalFrom: 0.33, normalTo: 0.66, dot: 0.78, value: 62), "62 ms"),
        (.off(.below), LineScale(normalFrom: 0.33, normalTo: 0.66, dot: 0.2, value: 30), "30 ms"),
        (.far(.above), LineScale(normalFrom: 0.33, normalTo: 0.66, dot: 0.97, value: 90), "90 ms"),
        (.far(.below), LineScale(normalFrom: 0.33, normalTo: 0.66, dot: 0, value: 10), "10 ms"),
    ]

    var body: some View {
        VStack(spacing: Theme.Spacing.s24) {
            ForEach(cases.indices, id: \.self) { index in
                let found = cases[index]
                GlassCard {
                    NormalPicture(
                        scale: found.1, mark: found.0, color: Theme.Palette.recovery, value: found.2, low: "34", high: "52 ms",
                        spoken: "\(found.2)\(found.0.map { ", \($0.words)" } ?? ""). Your normal 34 to 52 ms."
                    )
                }
            }
        }
        .padding(Theme.Spacing.edge)
        .background { BlobBackground() }
    }
}

#Preview("Light") { NormalPictureSheet().preferredColorScheme(.light) }
#Preview("Dark") { NormalPictureSheet().preferredColorScheme(.dark) }
#Preview("AX5") { ScrollView { NormalPictureSheet() }.dynamicTypeSize(.accessibility5) }
#endif
