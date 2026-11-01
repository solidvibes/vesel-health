import SwiftUI
import VeselCore

/// Every term in the glossary, grouped; a row opens the same sheet the titles open, without a "Yours" line.
struct WhatThingsMeanView: View {
    @Environment(\.showMeaning) private var showMeaning

    var body: some View {
        ZStack {
            BlobBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.s24) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
                        Text("What things mean")
                            .font(Theme.Typography.title)
                            .foregroundStyle(Theme.Palette.text)
                            .accessibilityAddTraits(.isHeader)
                        Text("What each number is, whether more is good, what's normal and what affects it.")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Glossary.groups, id: \.title) { group in
                        VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
                            Text(group.title)
                                .font(Theme.Typography.label)
                                .foregroundStyle(Theme.Palette.mutedText)
                                .accessibilityAddTraits(.isHeader)
                            GlassCard {
                                VStack(spacing: 0) {
                                    ForEach(Array(group.terms.enumerated()), id: \.element) { index, term in
                                        if index > 0 { Divider() }
                                        row(term)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.edge)
                .padding(.top, Theme.Spacing.s16)
                .padding(.bottom, Theme.Spacing.s32)
            }
            TopFade()
        }
        .navigationTitle("What things mean")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ term: Term) -> some View {
        Button {
            showMeaning(MeaningRequest(term: term))
        } label: {
            HStack(spacing: Theme.Spacing.s8) {
                Text(Glossary.meaning(term).title)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.text)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: Theme.Spacing.s8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Palette.mutedText)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Theme.Size.row)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows what it means")
    }
}

#if DEBUG
#Preview { NavigationStack { WhatThingsMeanView() } }
#endif
