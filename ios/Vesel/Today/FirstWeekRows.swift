import SwiftUI
import VeselCore

/// One line's first-week row: its name, how many more it needs, and a check for each night or day that came in.
/// A missed night or a day still to come is an empty ring. Opens the line's page.
struct FirstWeekRow: View {
    let title: String
    let row: FirstWeek.Row
    let color: Color
    let zone: TimeZone
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private static let size: CGFloat = 15

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
                let names =
                    typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.s4))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
                names {
                    Text(title)
                        .font(Theme.Typography.heading)
                        .foregroundStyle(Theme.Palette.mutedText)
                    if !typeSize.isAccessibilitySize { Spacer(minLength: Theme.Spacing.s8) }
                    Text(row.text)
                        .font(Theme.Typography.heading)
                        .foregroundStyle(Theme.Palette.text)
                }
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: Self.size, maximum: Self.size), spacing: Theme.Spacing.s8)], alignment: .leading,
                    spacing: Theme.Spacing.s8
                ) {
                    ForEach(Array(row.cells.enumerated()), id: \.offset) { _, cell in
                        mark(cell)
                    }
                }
            }
            .padding(.vertical, Theme.Spacing.s8)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.tapTarget, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(spoken)
        .accessibilityHint("Opens \(title)")
    }

    @ViewBuilder private func mark(_ cell: FirstWeek.Cell) -> some View {
        if cell == .checked {
            Circle()
                .fill(color)
                .frame(width: Self.size, height: Self.size)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(Theme.Palette.background)
                }
        } else {
            Circle()
                .strokeBorder(color.opacity(0.55), lineWidth: 1.5)
                .frame(width: Self.size, height: Self.size)
        }
    }

    /// "4 of 7 nights in, 3 more, normal from Sunday".
    private var spoken: String {
        let unit = row.line == .calm ? "days" : "nights"
        let total = row.line == .calm ? FirstWeek.calmDays : PersonalRange.minimumNights
        let progress = "\(row.checked) of \(total) \(unit) in"
        if row.line == .calm { return "\(progress), \(row.text)" }
        guard row.remaining > 0 else { return "\(progress), your normal shows tomorrow" }
        let from = row.normalFrom.map { ", normal from \(Formatters.weekday($0, zone: zone))" } ?? ""
        return "\(progress), \(row.remaining) more\(from)"
    }
}
