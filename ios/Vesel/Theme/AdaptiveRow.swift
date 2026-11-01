import SwiftUI

/// Label left and value right; at the accessibility text sizes the value goes below so no word breaks mid-way.
struct AdaptiveRow<Leading: View, Trailing: View>: View {
    var alignment: VerticalAlignment = .center
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Theme.Spacing.s4) {
                leading
                trailing
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: alignment, spacing: Theme.Spacing.s12) {
                leading
                Spacer(minLength: Theme.Spacing.s8)
                trailing
            }
        }
    }
}
