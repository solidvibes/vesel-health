import SwiftUI

/// A thin line with a short piece sliding across, for work with no known end. Still under Reduce Motion; hidden from VoiceOver.
struct IndeterminateLine: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let piece = width * 0.3
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.18))
                if !reduceMotion {
                    TimelineView(.animation) { context in
                        let phase = context.date.timeIntervalSince(start).truncatingRemainder(dividingBy: 1.6) / 1.6
                        Capsule()
                            .fill(color)
                            .frame(width: piece)
                            .offset(x: -piece + (width + piece) * phase)
                    }
                }
            }
            .clipShape(.capsule)
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}
