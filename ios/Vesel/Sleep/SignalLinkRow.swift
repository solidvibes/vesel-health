import SwiftUI
import VeselCore

/// One row that opens another signal's page: its name, its value and, where it has one, its mark against your normal; `note` (the
/// learning words) sits under the name. The whole row is the button. The page opens on `day`, in `period` for the window that ends there.
struct SignalLinkRow: View {
    let kind: PageKind
    let value: String
    var mark: NormalMark?
    var note: String?
    let day: DayKey
    var period: PagePeriod = .day
    @Environment(\.openPage) private var openPage

    var body: some View {
        Button {
            openPage(PageRoute(kind: kind, day: day, period: period))
        } label: {
            AdaptiveRow {
                VStack(alignment: .leading, spacing: Theme.Spacing.s4) {
                    Text(kind.title)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.text)
                    if let note {
                        Text(note)
                            .font(Theme.Typography.small)
                            .foregroundStyle(Theme.Palette.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } trailing: {
                HStack(spacing: Theme.Spacing.s8) {
                    Text(value)
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Palette.text)
                        .multilineTextAlignment(.trailing)
                    if let mark { MarkBadge(mark: mark) }
                }
            }
            .padding(.vertical, Theme.Spacing.s8)
            .frame(minHeight: Theme.Size.row)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(([kind.title, value] + [mark?.words, note].compactMap { $0 }).joined(separator: ", "))
        .accessibilityHint("Opens \(kind.title)")
    }
}
