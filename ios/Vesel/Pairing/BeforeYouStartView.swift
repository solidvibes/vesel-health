import SwiftUI

struct BeforeYouStartView: View {
    let model: PairingModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s24) {
            PairingHeader(
                step: 1,
                title: "Pair your Loop",
                message: "Vesel talks to your Polar Loop directly over Bluetooth. Nothing goes through Polar's or anyone else's cloud."
            )
            GlassCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.s16) {
                    point("link", "Your Loop pairs with one app at a time. Once it's paired with Vesel, Polar Flow stops syncing it.")
                    point("arrow.triangle.2.circlepath", "First open Polar Flow and sync once. The reset erases anything your Loop hasn't sent yet.")
                    point("xmark.circle", "Remove “Polar Loop” from Polar Flow and from iOS Settings › Bluetooth.")
                    point("arrow.counterclockwise", "Factory reset the Loop: put it on its charger and hold the reset button under the strap.")
                }
            }
            Button("I've reset it, start pairing", action: model.startLooking)
                .buttonStyle(.veselPrimary)
        }
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Theme.Palette.accent)
        }
    }
}

#if DEBUG
#Preview { PreviewHost(.unpaired) { environment in PreviewPairing(environment: environment) { BeforeYouStartView(model: $0) } } }
#endif
