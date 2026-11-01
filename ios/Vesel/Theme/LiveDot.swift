import SwiftUI

/// A green dot that pulses while the heart rate is live; it holds still with Reduce Motion on.
struct LiveDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(Theme.Palette.success)
            .frame(width: 10, height: 10)
            .background {
                Circle()
                    .fill(Theme.Palette.success.opacity(pulsing ? 0 : 0.5))
                    .scaleEffect(pulsing ? 2.4 : 1)
            }
            .onChange(of: reduceMotion, initial: true) {
                if reduceMotion {
                    withAnimation(nil) { pulsing = false }
                } else {
                    withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) { pulsing = true }
                }
            }
            .accessibilityLabel("live")
    }
}
