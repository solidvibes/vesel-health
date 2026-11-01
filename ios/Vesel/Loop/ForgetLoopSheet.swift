import SwiftUI

struct ForgetLoopSheet: View {
    let model: LoopSettingsModel
    let step: ForgetStep
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s20) {
            switch step {
            case .confirm:
                header("Forget this Loop?", "Vesel reads your Loop one last time, then resets it to factory settings. Your history stays on this iPhone.")
                Button("Forget this Loop") { Task { await model.confirmForget() } }
                    .buttonStyle(.veselDestructive)
                Button("Cancel") { dismiss() }
                    .buttonStyle(.veselSecondary)
            case .finalSync:
                progress("Reading your Loop one last time…")
            case .lost(let lastRead):
                header("Couldn't read your Loop", lostMessage(lastRead))
                Button("Reset anyway") { Task { await model.reset() } }
                    .buttonStyle(.veselDestructive)
                Button("Cancel") { dismiss() }
                    .buttonStyle(.veselSecondary)
            case .resetting:
                progress("Resetting your Loop…")
            case .done(let bandWasReset):
                header(
                    bandWasReset ? "Loop reset" : "Loop forgotten",
                    (bandWasReset ? "" : "Vesel couldn't reach the Loop to reset it. Put it on its charger and hold the reset button under the strap. ")
                        + "Then open iOS Settings › Bluetooth, tap ⓘ next to “Polar Loop” and choose Forget This Device."
                )
                Button("Done") { model.finishForgetting() }
                    .buttonStyle(.veselPrimary)
            }
        }
        .padding(Theme.Spacing.s24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.medium])
        .presentationCornerRadius(Theme.Corner.sheet)
        .presentationBackground(Theme.Palette.surface)
        .interactiveDismissDisabled(step != .confirm)
    }

    private func lostMessage(_ lastRead: Date?) -> String {
        guard let lastRead else { return "Vesel has never read this Loop. Everything on it will be lost if you reset it now." }
        return "Anything your Loop recorded since the last read (\(lastRead.formatted(date: .abbreviated, time: .shortened))) will be lost if you reset it now."
    }

    private func header(_ title: String, _ message: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
            Text(title)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Palette.text)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func progress(_ text: String) -> some View {
        HStack(spacing: Theme.Spacing.s16) {
            ProgressView()
            Text(text)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.text)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }
}

#if DEBUG
private struct PreviewForget: View {
    let step: ForgetStep

    var body: some View {
        PreviewHost { environment in
            ForgetLoopSheet(
                model: LoopSettingsModel(
                    database: environment.database,
                    clock: environment.clock,
                    bandSync: environment.bandSync,
                    pipeline: environment.pipeline,
                    forget: step,
                    backupSetUpError: nil,
                    runSync: { nil },
                    didForget: {}
                ), step: step)
        }
    }
}

#Preview("Confirm") { PreviewForget(step: .confirm) }
#Preview("Couldn't read") { PreviewForget(step: .lost(lastRead: nil)) }
#Preview("Done") { PreviewForget(step: .done(bandWasReset: true)) }
#endif
