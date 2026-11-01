import SwiftUI

extension View {
    /// The page's title in the top bar, faded in once the page's own big title has scrolled under the bar (`shown`). VoiceOver skips
    /// it: the big title is still there to read.
    func barTitle(_ title: String, shown: Bool) -> some View {
        modifier(BarTitle(title: title, shown: shown))
    }

    /// For the page's big title: fades out as the bar title fades in, so the two never show at once through the see-through bar.
    /// Masked, not hidden, so VoiceOver still reads it.
    func underBar(_ passed: Bool) -> some View {
        modifier(UnderBar(passed: passed))
    }
}

private struct UnderBar: ViewModifier {
    let passed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.mask {
            Rectangle()
                .opacity(passed ? 0 : 1)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: passed)
        }
    }
}

private struct BarTitle: ViewModifier {
    let title: String
    let shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .principal) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.Palette.text)
                    .opacity(shown ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: shown)
                    .accessibilityHidden(true)
            }
        }
    }
}
