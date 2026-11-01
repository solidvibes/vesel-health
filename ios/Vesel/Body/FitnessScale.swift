import SwiftUI
import VeselCore

/// "Younger · About your age · Older": a marker that slides in and settles in your band. No number. The card draws it small and still.
struct FitnessScale: View {
    enum Style { case page, card }

    let band: FitnessBand
    let style: Style
    @State private var settled = false
    @State private var glowing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var pageMarker: CGFloat = 32

    private var trackHeight: CGFloat { style == .page ? 14 : 8 }
    private var marker: CGFloat { style == .page ? min(pageMarker, 48) : 16 }
    private var index: Int { [FitnessBand.younger, .about, .older].firstIndex(of: band) ?? 1 }
    private var animates: Bool { style == .page }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
            scale
            if style == .page { labels }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(band.spoken)
        .task {
            guard animates, !reduceMotion else { settled = true; glowing = true; return }
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.spring(duration: 1.3, bounce: 0.22)) { settled = true }
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.easeOut(duration: 1.1)) { glowing = true }
        }
    }

    private var scale: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let segment = width / 3
            let target = segment * (CGFloat(index) + 0.5)
            let start = marker / 2
            ZStack(alignment: .leading) {
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { slot in
                        Capsule()
                            .fill(Theme.Palette.recovery.opacity(slot == index && glowing ? 0.5 : 0.16))
                            .frame(height: trackHeight)
                    }
                }
                .frame(height: marker)
                Circle()
                    .fill(Theme.Palette.recovery)
                    .frame(width: marker * 2.2, height: marker * 2.2)
                    .blur(radius: marker * 0.55)
                    .opacity(glowing ? 0.55 : 0)
                    .position(x: settled || !animates ? target : start, y: marker / 2)
                    .accessibilityHidden(true)
                Circle()
                    .fill(Theme.Palette.surface)
                    .overlay(Circle().stroke(Theme.Palette.recovery, lineWidth: style == .page ? 4 : 3))
                    .frame(width: marker, height: marker)
                    .opacity(settled || !animates ? 1 : 0.2)
                    .position(x: settled || !animates ? target : start, y: marker / 2)
            }
        }
        .frame(height: marker)
    }

    @ViewBuilder private var labels: some View {
        let titles = ["Younger", "About your age", "Older"]
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Theme.Spacing.s4) {
                ForEach(0..<3, id: \.self) { slot in
                    Label(titles[slot], systemImage: slot == index ? "checkmark.circle.fill" : "circle")
                        .font(slot == index ? Theme.Typography.label : Theme.Typography.small)
                        .foregroundStyle(slot == index ? Theme.Palette.text : Theme.Palette.mutedText)
                }
            }
        } else {
            HStack(alignment: .top, spacing: 3) {
                ForEach(0..<3, id: \.self) { slot in
                    Text(titles[slot])
                        .font(slot == index ? Theme.Typography.label : Theme.Typography.small)
                        .foregroundStyle(slot == index ? Theme.Palette.text : Theme.Palette.mutedText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}
