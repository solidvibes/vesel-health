import SwiftUI
import VeselCore
import VeselStorage

/// The recovery part of Night, one card: Polar's verdict, the sentence and why, what went into it, and how it is worked out.
struct RecoveryView: View {
    let model: RecoveryModel
    /// "Night by night" in a contributor's meaning sheet: open that signal's page on 4 weeks.
    let openContributor: (Contributor, DayKey) -> Void

    var body: some View {
        if let report = model.report {
            GlassCard { content(report) }
        } else if model.isLoaded && model.nightPending {
            EmptyState(systemImage: "heart", title: "Evaluating your night", message: "Recovery shows here once your Loop has it ready.")
        } else if model.isLoaded {
            EmptyState(
                systemImage: "heart",
                title: "Polar hasn't scored this night yet",
                message: "Recovery shows once the night is in."
            )
        } else {
            SkeletonBlock(height: 160)
        }
    }

    @ViewBuilder private func content(_ report: NightReport) -> some View {
        let when = YoursText.night(report.night, today: model.today, zone: model.zone)
        VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
            HStack(alignment: .center, spacing: Theme.Spacing.s8) {
                TermTitle(
                    term: .recovery, title: "Recovery", isHeader: true,
                    yours: report.status.map { "\(when): \($0.word), \($0.indicator) of 6 on Polar's Nightly Recharge." },
                    explanations: report.metrics[MetricKind.recoveryStatus].map { [("Polar's Nightly Recharge", $0.explanation)] } ?? []
                )
                Spacer(minLength: Theme.Spacing.s8)
                if let status = report.status {
                    Text("\(status.word.capitalizedFirst) · \(status.indicator) of 6")
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Palette.text)
                        .multilineTextAlignment(.trailing)
                }
            }
            if let headline = model.headline {
                Text(headline.sentence)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                if !headline.why.isEmpty {
                    Text(headline.why)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            let readings = report.contributors
            if !readings.isEmpty {
                Text("What went into it")
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, Theme.Spacing.s8)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(readings, id: \.contributor) { reading in
                        ContributorRow(
                            reading: reading, yours: YoursText.contributor(reading, when: when, units: model.units), units: model.units,
                            nightByNight: { openContributor(reading.contributor, report.night) }
                        )
                        if reading.contributor != readings.last?.contributor { Divider() }
                    }
                }
                Text(
                    TermLink.text(
                        "Green: the good side of your usual. Orange: the other side. Grey: within your usual.",
                        linking: "usual", to: .usualRange
                    )
                )
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Palette.mutedText)
                .fixedSize(horizontal: false, vertical: true)
            }

            Divider().padding(.top, Theme.Spacing.s4)
            HowItsWorkedOutRow(framed: false, explanations: workedOut(report).map(\.1), labels: workedOut(report).map(\.0))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Your normal, Nightly Recharge, the sentence, then each contributor.
    private func workedOut(_ report: NightReport) -> [(String, Explanation)] {
        var rows: [(String, Explanation)] = []
        if let metric = report.metrics[MetricKind.recoveryStatus], report.status != nil {
            rows.append(("Your normal", model.lines.recovery.explanation))
            rows.append(("Polar's Nightly Recharge", metric.explanation))
        }
        if let headline = model.headline { rows.append(("The sentence", headline.explanation)) }
        rows += report.contributors.map { ($0.contributor.title, $0.explanation) }
        return rows
    }
}

#if DEBUG
private struct PreviewRecovery: View {
    @State private var model: RecoveryModel

    init(environment: AppEnvironment) {
        _model = State(
            initialValue: RecoveryModel(
                database: environment.database, clock: environment.clock, status: environment.status, units: environment.units, day: environment.clock.today
            ))
    }

    var body: some View {
        ScrollView {
            RecoveryView(model: model) { _, _ in }
                .padding(Theme.Spacing.edge)
        }
        .background { BlobBackground() }
        .task { await model.observe() }
    }
}

#Preview("Normal") { PreviewHost { PreviewRecovery(environment: $0) } }
#Preview("First day") { PreviewHost(.firstDay) { PreviewRecovery(environment: $0) } }
#endif
