import SwiftUI
import VeselCore

/// A reading's mark against your normal: a coloured circle with its symbol. Colour is never the only sign, and the
/// badge speaks nothing itself: the row it sits in says `NormalMark.words`.
struct MarkBadge: View {
    let mark: NormalMark
    @ScaledMetric(relativeTo: .footnote) private var size: CGFloat = 24

    var body: some View {
        Image(systemName: mark.symbol)
            .font(.footnote.weight(.bold))
            .foregroundStyle(Theme.Palette.markInk(mark))
            .frame(width: size, height: size)
            .background(Theme.Palette.markChip(mark), in: Circle())
            .accessibilityHidden(true)
    }
}

#if DEBUG
private struct MarkBadgeSheet: View {
    let marks: [NormalMark] = [.inside, .better(.above), .better(.below), .off(.above), .off(.below), .far(.above), .far(.below)]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
            ForEach(marks, id: \.words) { mark in
                HStack(spacing: Theme.Spacing.s12) {
                    MarkBadge(mark: mark)
                    Text(mark.words).font(Theme.Typography.body)
                }
            }
        }
        .padding(Theme.Spacing.edge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.background)
    }
}

#Preview("Light") { MarkBadgeSheet().preferredColorScheme(.light) }
#Preview("Dark") { MarkBadgeSheet().preferredColorScheme(.dark) }
#Preview("AX5") { MarkBadgeSheet().dynamicTypeSize(.accessibility5) }
#endif
