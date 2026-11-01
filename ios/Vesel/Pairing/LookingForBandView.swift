import SwiftUI

struct LookingForBandView: View {
    let model: PairingModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s24) {
            PairingHeader(
                step: 2,
                title: "Looking for your Loop",
                message: "Hold it within 1 m of your iPhone. When iOS asks to pair, tap Pair."
            )
            switch model.looking {
            case .searching:
                GlassCard {
                    HStack(spacing: Theme.Spacing.s16) {
                        ProgressView()
                        Text("Searching…")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.text)
                    }
                    .frame(maxWidth: .infinity, minHeight: Theme.Size.tapTarget, alignment: .leading)
                }
            case .notFound:
                ErrorCard(
                    title: "No Loop found",
                    message: "Make sure it was factory reset and is close to your iPhone.",
                    actionTitle: "Keep looking",
                    action: model.startLooking
                )
            case .refused:
                ErrorCard(
                    title: "The Loop didn't pair",
                    message:
                        "It's probably still paired with another app or phone. Remove “Polar Loop” from iOS Settings › Bluetooth, factory reset it on its charger, then try again.",
                    actionTitle: "Try again",
                    action: model.startLooking
                )
            }
            Button("Cancel", action: model.cancel)
                .buttonStyle(.veselSecondary)
        }
    }
}

#if DEBUG
#Preview("Searching") { PreviewHost(.unpaired) { environment in PreviewPairing(environment: environment) { LookingForBandView(model: $0) } } }
#Preview("Not found") {
    PreviewHost(.unpaired) { environment in PreviewPairing(environment: environment, looking: .notFound) { LookingForBandView(model: $0) } }
}
#Preview("Refused") {
    PreviewHost(.unpaired) { environment in PreviewPairing(environment: environment, looking: .refused) { LookingForBandView(model: $0) } }
}
#endif
