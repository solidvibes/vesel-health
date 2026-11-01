import SwiftUI

/// Shown instead of the app when the database won't open. It never deletes or resets anything and never shows the error.
struct StorageProblemView: View {
    let problem: StorageProblem
    let tryAgain: () -> Void

    var body: some View {
        ZStack {
            BlobBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.s24) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
                        Text(title)
                            .font(Theme.Typography.title)
                            .foregroundStyle(Theme.Palette.text)
                            .accessibilityAddTraits(.isHeader)
                        Text(message)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.mutedText)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    if problem == .couldNotOpen {
                        Button("Try again", action: tryAgain)
                            .buttonStyle(.veselPrimary)
                    }
                }
                .padding(.horizontal, Theme.Spacing.edge)
                .padding(.vertical, Theme.Spacing.s48)
            }
        }
    }

    private var title: String {
        switch problem {
        case .olderApp: "Vesel needs an update"
        case .setUp: "Vesel isn't set up right"
        case .couldNotOpen: "Vesel can't open your data right now"
        }
    }

    private var message: String {
        switch problem {
        case .olderApp:
            "Your data on this phone was saved by a newer version of Vesel. Install the newer version to open it. Nothing has been deleted."
        case .setUp:
            "This build is missing its shared data folder. Rebuild it with your own bundle prefix (see the README)."
        case .couldNotOpen:
            "Your data is still on this phone. Unlock your iPhone, then try again."
        }
    }
}

#if DEBUG
#Preview("Older app") { StorageProblemView(problem: .olderApp, tryAgain: {}) }
#Preview("Set up") { StorageProblemView(problem: .setUp, tryAgain: {}) }
#Preview("Couldn't open") { StorageProblemView(problem: .couldNotOpen, tryAgain: {}) }
#endif
