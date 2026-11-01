import SwiftUI
import VeselCore

/// What a screen hands the one meaning sheet: the term, its own line for the day shown, and the explanations that sit folded inside.
struct MeaningRequest: Identifiable {
    let id = UUID()
    let term: Term
    /// The screen's number for the day shown, as a sentence; nil where there is no day (the list, a term link).
    var yours: String?
    var explanations: [(label: String, explanation: Explanation)] = []
    /// One more button under the number ("Night by night"); the sheet closes first.
    var more: (title: String, action: () -> Void)?
}

/// Opens the meaning sheet hosted by `MainTabs`: `@Environment(\.showMeaning) var showMeaning`, then `showMeaning(request)`.
struct ShowMeaning: Sendable {
    let action: @MainActor (MeaningRequest) -> Void

    @MainActor func callAsFunction(_ request: MeaningRequest) { action(request) }
}

extension EnvironmentValues {
    @Entry var showMeaning = ShowMeaning(action: { _ in })
}

/// One term's meaning: the glossary's sections, the screen's own number, how the band knows, and how it's worked out folded.
struct MeaningSheet: View {
    let request: MeaningRequest
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    private var meaning: Meaning { Glossary.meaning(request.term) }

    var body: some View {
        NavigationStack {
            ZStack {
                BlobBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s20) {
                        Text(meaning.title)
                            .font(Theme.Typography.title)
                            .foregroundStyle(Theme.Palette.text)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(meaning.sections, id: \.heading) { section($0.heading, $0.text) }
                        if let yours = request.yours { yoursCard(yours) }
                        if let more = request.more {
                            Button(more.title) {
                                dismiss()
                                more.action()
                            }
                            .buttonStyle(.veselSecondary)
                        }
                        if let how = meaning.howTheBandKnows { section("How the band knows", how) }
                        if !request.explanations.isEmpty || meaning.workedOut != nil {
                            HowItsWorkedOutRow(
                                explanations: request.explanations.map(\.explanation),
                                labels: request.explanations.map(\.label),
                                note: meaning.workedOut
                            )
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

    private func section(_ heading: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s4) {
            Text(heading)
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Palette.mutedText)
                .accessibilityAddTraits(.isHeader)
            Text(text)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func yoursCard(_ text: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s4) {
                Text("Yours")
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .accessibilityAddTraits(.isHeader)
                Text(text)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#if DEBUG
#Preview("Term") { MeaningSheet(request: MeaningRequest(term: .remSleep)) }
#Preview("With your number") { MeaningSheet(request: MeaningRequest(term: .remSleep, yours: "Last night you had 1 h 32 min of REM sleep.")) }
#endif
