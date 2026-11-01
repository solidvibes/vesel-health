import SwiftUI

/// 52 pt row: label left, value right.
struct ListRow: View {
    let label: String
    let value: String

    var body: some View {
        AdaptiveRow {
            Text(label)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.text)
        } trailing: {
            Text(value)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.mutedText)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: Theme.Size.row)
        .accessibilityElement(children: .combine)
    }
}
