import SwiftUI
import VeselCore
import VeselStorage

/// Loop & settings › Apple Health: one switch, and how the last write went under it.
struct HealthSection: View {
    let isOn: Bool
    let lines: [String]
    let setOn: @MainActor @Sendable (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
            Text("Apple Health")
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Palette.mutedText)
            GlassCard {
                Toggle("Write to Apple Health", isOn: Binding(get: { isOn }, set: setOn))
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.text)
                    .tint(Theme.Palette.accent)
                    .frame(minHeight: Theme.Size.row)
            }
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#if DEBUG
private struct PreviewHealthSection: View {
    let status: HealthStatus
    private let now = Date(timeIntervalSince1970: 1_793_091_600)

    var body: some View {
        ZStack {
            BlobBackground()
            HealthSection(isOn: status.isOn, lines: LoopSettingsModel.healthLines(status, now: now), setOn: { _ in })
                .padding(.horizontal, Theme.Spacing.edge)
        }
    }

    static func run(_ outcome: HealthRun.Outcome = .written, daysToGo: Int = 0, notAllowed: [HealthKind] = [], wroteAny: Bool = true) -> HealthRun {
        HealthRun(at: Date(timeIntervalSince1970: 1_793_091_060), outcome: outcome, daysToGo: daysToGo, notAllowed: notAllowed, wroteAny: wroteAny)
    }
}

#Preview("Off") { PreviewHealthSection(status: HealthStatus(isOn: false, lastRun: nil)) }
#Preview("Writing") { PreviewHealthSection(status: HealthStatus(isOn: true, lastRun: PreviewHealthSection.run(daysToGo: 42))) }
#Preview("Up to date") { PreviewHealthSection(status: HealthStatus(isOn: true, lastRun: PreviewHealthSection.run())) }
#Preview("Nothing yet") { PreviewHealthSection(status: HealthStatus(isOn: true, lastRun: PreviewHealthSection.run(wroteAny: false))) }
#Preview("Some not allowed") {
    PreviewHealthSection(status: HealthStatus(isOn: true, lastRun: PreviewHealthSection.run(notAllowed: [.sleep, .steps])))
}
#Preview("Nothing allowed") {
    PreviewHealthSection(status: HealthStatus(isOn: true, lastRun: PreviewHealthSection.run(notAllowed: HealthKind.allCases)))
}
#Preview("Failed") { PreviewHealthSection(status: HealthStatus(isOn: true, lastRun: PreviewHealthSection.run(.failed))) }
#Preview("Off after writing") { PreviewHealthSection(status: HealthStatus(isOn: false, lastRun: PreviewHealthSection.run())) }
#endif
