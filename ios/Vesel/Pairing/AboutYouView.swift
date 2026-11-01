import SwiftUI
import VeselCore

struct AboutYouView: View {
    @Bindable var model: PairingModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s24) {
            PairingHeader(
                step: 3,
                title: "About you",
                message: "Your Loop needs these for its sleep and calorie maths. They stay on the Loop and this iPhone."
            )
            GlassCard {
                AboutYouFields(draft: $model.draft, currentYear: model.currentYear, units: model.units)
            }
            if model.setupFailed {
                ErrorCard(
                    title: "Setup didn't finish",
                    message: "Your Loop didn't take the settings. Keep it close to your iPhone and try again.",
                    actionTitle: "Try again",
                    action: model.finish
                )
            } else {
                Button(action: model.finish) {
                    if model.finishing {
                        ProgressView().tint(Theme.Palette.onPrimary)
                    } else {
                        Text("Finish")
                    }
                }
                .buttonStyle(.veselPrimary)
                .disabled(!model.canFinish)
            }
        }
    }
}

/// Birth year, height, weight, sex and sleep goal, with their checks. Pairing step 3 and the About you editor; the editor
/// also shows waist and another device's VO2max, which stay on the phone. Height, weight and waist follow the units setting.
struct AboutYouFields: View {
    @Binding var draft: ProfileDraft
    let currentYear: Int
    let units: Units
    var showsOptional = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s16) {
            NumberField(label: "Birth year", placeholder: "1990", text: $draft.birthYear, error: draft.birthYearError(currentYear: currentYear))
            if draft.units == .metric {
                NumberField(label: "Height (cm)", placeholder: "175", text: $draft.height, error: draft.heightError)
                NumberField(label: "Weight (kg)", placeholder: "70", text: $draft.weight, error: draft.weightError)
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
                    Text("Height")
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Palette.text)
                        .accessibilityHidden(true)
                    HStack(alignment: .top, spacing: Theme.Spacing.s12) {
                        NumberField(label: "ft", placeholder: "5", text: $draft.heightFeet, error: nil, spokenLabel: "Height, feet")
                        NumberField(label: "in", placeholder: "9", text: $draft.heightInches, error: nil, spokenLabel: "Height, inches")
                    }
                    if let error = draft.heightError {
                        FieldError(text: error)
                    }
                }
                NumberField(label: "Weight (lb)", placeholder: "155", text: $draft.weight, error: draft.weightError)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
                Text("Biological sex")
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Palette.text)
                Picker("Biological sex", selection: $draft.sex) {
                    Text("Male").tag(Sex?.some(.male))
                    Text("Female").tag(Sex?.some(.female))
                }
                .pickerStyle(.segmented)
                .frame(minHeight: Theme.Size.tapTarget)
            }
            Stepper(value: $draft.sleepGoalHours, in: 5...11, step: 0.5) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s4) {
                    Text("Sleep goal")
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Palette.text)
                    Text(draft.sleepGoalHours.formatted(.number.precision(.fractionLength(0...1))) + " h")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.mutedText)
                }
            }
            .frame(minHeight: Theme.Size.tapTarget)
            if showsOptional {
                NumberField(
                    label: draft.units == .metric ? "Waist (cm)" : "Waist (in)", placeholder: "Optional", text: $draft.waist,
                    error: draft.waistError,
                    hint: "Measured around your belly button. Waist helps estimate your heart fitness. It stays on this phone.")
                NumberField(
                    label: "VO2max from another device (ml/kg/min)", placeholder: "Optional", text: $draft.measuredVO2max,
                    error: draft.measuredVO2maxError, hint: "e.g. from a Garmin watch")
            }
        }
        .onChange(of: units, initial: true) { draft.switchUnits(to: units) }
    }
}

/// Label above, 48 pt tall; an error gets a red border, an icon and words.
private struct NumberField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let error: String?
    var hint: String?
    /// For VoiceOver when the label alone doesn't say it ("ft").
    var spokenLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
            Text(label)
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Palette.text)
            TextField(placeholder, text: $text)
                .keyboardType(.numberPad)
                .font(Theme.Typography.body)
                .padding(.horizontal, Theme.Spacing.s12)
                .frame(minHeight: Theme.Size.tapTarget)
                .background(Theme.Palette.surface.opacity(0.6), in: .rect(cornerRadius: Theme.Corner.small))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Corner.small)
                        .stroke(error == nil ? Theme.Palette.mutedText.opacity(0.3) : Theme.Palette.error, lineWidth: error == nil ? 1 : 2)
                }
                .accessibilityLabel(spokenLabel ?? label)
            if let error {
                FieldError(text: error)
            } else if let hint {
                Text(hint)
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct FieldError: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.circle")
            .font(Theme.Typography.small)
            .foregroundStyle(Theme.Palette.error)
    }
}

#if DEBUG
#Preview { PreviewHost(.unpaired) { environment in PreviewPairing(environment: environment) { AboutYouView(model: $0) } } }
#endif
