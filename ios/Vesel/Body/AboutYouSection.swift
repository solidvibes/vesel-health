import SwiftUI
import VeselCore

/// Body's About you rows: the Units switch, then the profile; any profile row opens the editor.
struct AboutYouSection: View {
    let model: AboutYouModel
    let profile: Profile

    var body: some View {
        unitsSwitch
        Divider()
        row("Height", model.units.heightText(cm: profile.heightCm))
        Divider()
        row("Weight", model.units.weightText(kg: profile.weightKg))
        Divider()
        row("Birth year", String(profile.birthYear))
        Divider()
        row("Sex", profile.sex == .male ? "Male" : "Female")
        Divider()
        row("Sleep goal", (Double(profile.sleepGoalMinutes) / 60).formatted(.number.precision(.fractionLength(0...1))) + " h")
        Divider()
        row("Waist", profile.waistCm.map { model.units.waistText(cm: $0) } ?? "Not set")
        Divider()
        row("VO2max from another device", profile.measuredVO2max.map { "\(Int($0.rounded())) ml/kg/min" } ?? "Not set")
    }

    /// Saves at once; only changes how the rows and fields are written, never what is on the Loop.
    private var unitsSwitch: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
            Text("Units")
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Palette.text)
            Picker("Units", selection: Binding(get: { model.units }, set: { units in Task { await model.setUnits(units) } })) {
                Text("Metric").tag(Units.metric)
                Text("US").tag(Units.us)
            }
            .pickerStyle(.segmented)
            .frame(minHeight: Theme.Size.tapTarget)
        }
        .padding(.vertical, Theme.Spacing.s8)
    }

    private func row(_ label: String, _ value: String) -> some View {
        Button(action: model.editProfile) {
            HStack(spacing: Theme.Spacing.s12) {
                AdaptiveRow {
                    Text(label)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.text)
                } trailing: {
                    Text(value)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.mutedText)
                        .multilineTextAlignment(.trailing)
                }
                Image(systemName: "chevron.right")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Theme.Size.row)
            .contentShape(.rect)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens About you to change it")
        }
        .buttonStyle(.plain)
    }
}

/// All About you fields, saved to the band first and then the phone. On failure the edit stays and nothing is stored.
struct AboutYouEditView: View {
    let model: AboutYouModel
    private let stored: Profile
    @State private var draft: ProfileDraft
    @Environment(\.dismiss) private var dismiss

    init(model: AboutYouModel, stored: Profile) {
        self.model = model
        self.stored = stored
        _draft = State(initialValue: ProfileDraft(profile: stored, units: model.units))
    }

    private var changed: Profile? {
        draft.profile(currentYear: model.currentYear).flatMap { $0 == stored ? nil : $0 }
    }

    var body: some View {
        ZStack {
            BlobBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.s24) {
                    if model.profileNotSaved {
                        ErrorCard(
                            title: "Not saved",
                            message: "Your Loop didn't take the change, so nothing changed on your phone either. Keep the Loop close and try again.",
                            actionTitle: "Try again",
                            action: save
                        )
                    }
                    GlassCard {
                        AboutYouFields(draft: $draft, currentYear: model.currentYear, units: model.units, showsOptional: true)
                    }
                    .disabled(model.savingProfile)
                    Text("Saving sends these to your Loop, except waist and VO2max. Your Loop may take a few nights to settle its recovery again.")
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Palette.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                    if model.savingProfile {
                        HStack(spacing: Theme.Spacing.s12) {
                            ProgressView()
                            Text("Saving to your Loop…")
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Palette.text)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, Theme.Spacing.edge)
                .padding(.top, Theme.Spacing.s16)
                .padding(.bottom, Theme.Spacing.s32)
            }
            .scrollDismissesKeyboard(.interactively)
            TopFade()
        }
        .navigationTitle("About you")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(changed == nil || model.savingProfile)
            }
        }
    }

    private func save() {
        guard let profile = changed ?? (model.profileNotSaved ? draft.profile(currentYear: model.currentYear) : nil) else { return }
        Task {
            if await model.saveProfile(profile) {
                dismiss()
            } else if model.profileNotSaved {
                AccessibilityNotification.Announcement("Not saved").post()
            }
        }
    }
}
