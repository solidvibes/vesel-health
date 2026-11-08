import SwiftUI

/// How to restart a stuck Loop by hand. A restart keeps its data and its pairing; on the charger the same press wipes it.
struct RestartLoopSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    private let steps = [
        ("Take it off the charger", "On the charger, the same press resets everything and unpairs it."),
        ("Press the tiny button with a pin", "It sits on top of the Loop, under the band. A short press is enough."),
        ("Wait half a minute, then sync", "Vesel finds it again and sets its clock."),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                BlobBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s20) {
                        Text("Restart your Loop")
                            .font(Theme.Typography.title)
                            .foregroundStyle(Theme.Palette.text)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s12) {
                                Text("\(index + 1)")
                                    .font(Theme.Typography.heading)
                                    .foregroundStyle(Theme.Palette.mutedText)
                                VStack(alignment: .leading, spacing: Theme.Spacing.s4) {
                                    Text(step.0)
                                        .font(Theme.Typography.heading)
                                        .foregroundStyle(Theme.Palette.text)
                                    Text(step.1)
                                        .font(Theme.Typography.body)
                                        .foregroundStyle(Theme.Palette.mutedText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.edge)
                    .padding(.top, Theme.Spacing.s8)
                    .padding(.bottom, Theme.Spacing.s32)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
    }
}

#Preview {
    RestartLoopSheet()
}
