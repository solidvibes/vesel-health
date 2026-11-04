import SwiftUI
import VeselCore
import VeselStorage

/// What went into Recovery, one card: a row per contributor with its value and mark, and how it is worked out.
struct RecoveryView: View {
    let model: RecoveryModel
    /// A contributor's row opens that signal's page for the night.
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
        VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
            let readings = report.contributors
            if !readings.isEmpty {
                Text("What went into it")
                    .font(Theme.Typography.heading)
                    .foregroundStyle(Theme.Palette.text)
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(readings, id: \.contributor) { reading in
                        ContributorRow(reading: reading, units: model.units) { openContributor(reading.contributor, report.night) }
                        if reading.contributor != readings.last?.contributor { Divider() }
                    }
                }
                if let line = model.quietLine {
                    Text(line)
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Palette.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider().padding(.top, Theme.Spacing.s4)
            }
            HowItsWorkedOutRow(framed: false, explanations: workedOut(report).map(\.1), labels: workedOut(report).map(\.0))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Polar's Nightly Recharge, your normal, then each contributor.
    private func workedOut(_ report: NightReport) -> [(String, Explanation)] {
        var rows: [(String, Explanation)] = []
        if let metric = report.metrics[MetricKind.recoveryStatus], report.status != nil {
            rows.append(("Polar's Nightly Recharge", metric.explanation))
            rows.append(("Your normal", model.lines.recovery.explanation))
        }
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
