import SwiftUI
import VeselCore

/// Loop & settings → Workouts: the Loop's training detection (band first, then phone) and the owner's sports.
struct WorkoutSettingsView: View {
    @State private var model: WorkoutSettingsModel
    /// The slider's own value while dragging; follows the model otherwise.
    @State private var sensitivity: Double = 50
    @State private var location = LocationPermission()
    @Environment(\.openURL) private var openURL

    init(environment: AppEnvironment) {
        let pipeline = environment.pipeline
        _model = State(
            initialValue: WorkoutSettingsModel(
                database: environment.database,
                idle: { await pipeline.idle() },
                writeDetection: { await pipeline.writeWorkoutDetection($0) }
            ))
    }

    var body: some View {
        ZStack {
            BlobBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.s24) {
                    if model.failed != nil {
                        ErrorCard(
                            title: "Not saved",
                            message: "Your Loop didn't take the change, so nothing changed on your phone either. Keep the Loop close and try again.",
                            actionTitle: "Try again",
                            action: { Task { await model.tryAgain() } }
                        )
                    }
                    section("On your Loop") {
                        if let detection = model.detection {
                            loopRows(detection)
                        } else if model.isLoaded {
                            ListRow(label: "Notice workouts by itself", value: "Set up at the next read")
                        }
                    }
                    .disabled(model.saving)
                    if model.saving {
                        HStack(spacing: Theme.Spacing.s12) {
                            ProgressView()
                            Text("Saving to your Loop…")
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Palette.text)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    note("Your Loop starts and ends a workout by itself. Higher sensitivity notices workouts more easily.")
                    section("On your phone") {
                        toggle(
                            "Record my route",
                            isOn: Binding(
                                get: { model.routeOn },
                                set: { on in
                                    Task { await model.setRoute(on: on) }
                                    if on { location.ask() }
                                }
                            ))
                        if model.routeOn { locationRow }
                    }
                    note("Only during a workout your Loop noticed. The route stays on your phone and your Mac.")
                    section("Your sports") {
                        ForEach(Array(WorkoutSport.allCases.enumerated()), id: \.element) { index, sport in
                            if index > 0 { Divider() }
                            toggle(
                                sport.name,
                                isOn: Binding(
                                    get: { model.sports.contains(sport) },
                                    set: { on in Task { await model.setSport(sport, on: on) } }
                                ))
                        }
                    }
                    note("Vesel guesses a workout's sport only from these.")
                }
                .padding(.horizontal, Theme.Spacing.edge)
                .padding(.top, Theme.Spacing.s16)
                .padding(.bottom, Theme.Spacing.s32)
            }
            TopFade()
        }
        .navigationTitle("Workouts")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .onChange(of: model.detection?.sensitivity, initial: true) { _, new in
            if let new { sensitivity = Double(new) }
        }
        .onChange(of: model.failed) { _, failed in
            if failed != nil { AccessibilityNotification.Announcement("Not saved").post() }
        }
    }

    @ViewBuilder
    private func loopRows(_ detection: WorkoutDetection) -> some View {
        toggle(
            "Notice workouts by itself",
            isOn: Binding(
                get: { detection.isOn },
                set: { on in save { $0.isOn = on } }
            ))
        Divider()
        VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
            Text("Sensitivity")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.text)
            Slider(value: $sensitivity, in: 0...100, step: 5) {
                Text("Sensitivity")
            } minimumValueLabel: {
                Text("Rarely").font(Theme.Typography.small)
            } maximumValueLabel: {
                Text("Easily").font(Theme.Typography.small)
            } onEditingChanged: { editing in
                if !editing { save { $0.sensitivity = Int(sensitivity) } }
            }
            .foregroundStyle(Theme.Palette.mutedText)
            .tint(Theme.Palette.accent)
            .accessibilityValue("\(Int(sensitivity)) of 100")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: sensitivity = min(100, sensitivity + 5)
                case .decrement: sensitivity = max(0, sensitivity - 5)
                @unknown default: return
                }
                save { $0.sensitivity = Int(sensitivity) }
            }
        }
        .padding(.vertical, Theme.Spacing.s12)
        .disabled(!detection.isOn)
        Divider()
        AdaptiveRow {
            Text("Shortest workout")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.text)
        } trailing: {
            Picker(
                "Shortest workout",
                selection: Binding(
                    get: { detection.minimumMinutes },
                    set: { minutes in save { $0.minimumMinutes = minutes } }
                )
            ) {
                ForEach(shortestChoices(detection), id: \.self) { Text("\($0) min").tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(Theme.Palette.accent)
        }
        .frame(minHeight: Theme.Size.row)
        .disabled(!detection.isOn)
    }

    @ViewBuilder
    private var locationRow: some View {
        switch location.state {
        case .notAsked:
            Divider()
            AdaptiveRow {
                Text("Needs location")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.mutedText)
            } trailing: {
                Button("Allow") { location.ask() }
                    .buttonStyle(.borderless)
                    .font(Theme.Typography.body.weight(.semibold))
                    .tint(Theme.Palette.accent)
                    .frame(minHeight: Theme.Size.tapTarget)
                    .accessibilityLabel("Allow location")
            }
            .frame(minHeight: Theme.Size.row)
        case .off:
            Divider()
            settingsRow("Location is off for Vesel in iOS Settings")
        case .whileUsing:
            Divider()
            settingsRow("Routes start only while Vesel is open. Allow location Always to record from your Loop's start.")
        case .always:
            EmptyView()
        }
    }

    private func settingsRow(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
            Text(text)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.mutedText)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(.borderless)
            .font(Theme.Typography.body.weight(.semibold))
            .tint(Theme.Palette.accent)
            .frame(minHeight: Theme.Size.tapTarget)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Theme.Spacing.s8)
    }

    /// The Loop's own minimum stays pickable when it isn't one of the usual lengths.
    private func shortestChoices(_ detection: WorkoutDetection) -> [Int] {
        Set(WorkoutSettingsModel.shortestChoices + [detection.minimumMinutes]).sorted()
    }

    private func save(_ change: (inout WorkoutDetection) -> Void) {
        guard var changed = model.detection else { return }
        change(&changed)
        Task { await model.setDetection(changed) }
    }

    private func toggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Palette.text)
            .tint(Theme.Palette.accent)
            .frame(minHeight: Theme.Size.row)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.small)
            .foregroundStyle(Theme.Palette.mutedText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
            Text(title)
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Palette.mutedText)
                .accessibilityAddTraits(.isHeader)
            GlassCard {
                VStack(spacing: 0) { content() }
            }
        }
    }
}

#if DEBUG
#Preview("Normal") {
    PreviewHost { environment in
        NavigationStack { WorkoutSettingsView(environment: environment) }
    }
}
#endif
