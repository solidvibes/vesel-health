import SwiftUI

/// A grey placeholder block that softly pulses while something loads.
struct SkeletonBlock: View {
    var height: CGFloat = 20
    var width: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Corner.small)
            .fill(Theme.Palette.mutedText.opacity(dim ? 0.12 : 0.24))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
            }
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview {
    VStack(spacing: Theme.Spacing.s12) {
        SkeletonBlock(height: 40)
        SkeletonBlock(height: 160)
        SkeletonBlock(height: 20, width: 120)
    }
    .padding(Theme.Spacing.edge)
    .background { BlobBackground() }
}
#endif
