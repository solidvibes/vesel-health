import SwiftUI

/// First run: Before you start → Looking for the band → About you → Today.
struct PairingFlow: View {
    @State private var model: PairingModel

    init(environment: AppEnvironment) {
        _model = State(
            initialValue: PairingModel(
                bandSync: environment.bandSync,
                database: environment.database,
                clock: environment.clock,
                units: environment.units,
                launchStep: environment.launch.pairingStep,
                didPair: environment.didPair
            ))
    }

    var body: some View {
        ZStack {
            BlobBackground()
            ScrollView {
                Group {
                    switch model.step {
                    case .before: BeforeYouStartView(model: model)
                    case .looking: LookingForBandView(model: model)
                    case .aboutYou: AboutYouView(model: model)
                    }
                }
                .padding(.horizontal, Theme.Spacing.edge)
                .padding(.top, Theme.Spacing.s32)
                .padding(.bottom, Theme.Spacing.s24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .animation(.default, value: model.step)
    }
}

/// Step title with "Step n of 3" above it.
struct PairingHeader: View {
    let step: Int
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
            Text("Step \(step) of 3")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Palette.mutedText)
            Text(title)
                .font(Theme.Typography.display)
                .foregroundStyle(Theme.Palette.text)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
