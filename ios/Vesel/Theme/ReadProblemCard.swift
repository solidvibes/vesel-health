import SwiftUI

/// A screen couldn't read its data: one calm card in place of the skeleton. Never shows the error itself.
struct ReadProblemCard: View {
    let tryAgain: () -> Void

    var body: some View {
        ErrorCard(
            title: "Couldn't show this",
            message: "Vesel couldn't read this just now. Your data is still on this phone.",
            actionTitle: "Try again",
            action: tryAgain
        )
    }
}

#if DEBUG
#Preview {
    ReadProblemCard(tryAgain: {})
        .padding(Theme.Spacing.edge)
        .background { BlobBackground() }
}
#endif
