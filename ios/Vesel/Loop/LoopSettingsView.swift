import SwiftUI
import VeselCore
import VeselSync

/// Band status, live heart rate, sync, band storage, alerts, help, Mac backup, Forget this Loop.
struct LoopSettingsView: View {
    @State private var model: LoopSettingsModel
    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
        let continuedRead = environment.continuedRead
        _model = State(
            initialValue: LoopSettingsModel(
                database: environment.database,
                clock: environment.clock,
                bandSync: environment.bandSync,
                pipeline: environment.pipeline,
                forget: environment.launch.forgetSheet,
                backupSetUpError: environment.launchBackupError,
                runSync: { await continuedRead.sync(.manual) },
                didForget: environment.didForget
            ))
    }

    var body: some View {
        ZStack {
            BlobBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.s24) {
                    section("Band") {
                        ListRow(label: "Status", value: connectionText)
                        Divider()
                        ListRow(label: "Battery", value: batteryText)
                        Divider()
                        ListRow(label: "Heart rate now", value: liveHeartRateText)
                    }
                    wristSection
                    section("Sync") {
                        NavigationLink(value: TodayRoute.syncing) {
                            HStack(spacing: Theme.Spacing.s8) {
                                ListRow(label: "Syncing", value: lastReadText)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Theme.Palette.mutedText)
                                    .accessibilityHidden(true)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        Divider()
                        ListRow(label: "Mac backup", value: backupText)
                        Divider()
                        ListRow(
                            label: "Band storage used",
                            value: model.storageUsedShare.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "Not read yet")
                    }
                    if model.storageIsHigh {
                        ErrorCard(
                            title: "Band storage is filling up",
                            message:
                                "Vesel clears what it has stored, up to the day before yesterday. Training sessions, sleep scores and skin-contact files aren't read by Vesel yet, so they stay on the band."
                        )
                    }
                    section("Alerts") {
                        ForEach(Array(AlertKind.allCases.enumerated()), id: \.element) { index, kind in
                            if index > 0 { Divider() }
                            Toggle(
                                kind.title,
                                isOn: Binding(
                                    get: { model.alerts.isOn(kind) },
                                    set: { on in Task { await model.setAlert(kind, on: on) } }
                                )
                            )
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.text)
                            .tint(Theme.Palette.accent)
                            .frame(minHeight: Theme.Size.row)
                        }
                    }
                    if model.notificationsDenied {
                        Text("Notifications are off for Vesel in iOS Settings, so alerts can't reach you.")
                            .font(Theme.Typography.small)
                            .foregroundStyle(Theme.Palette.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    section("Help") {
                        NavigationLink(value: TodayRoute.meanings) {
                            HStack(spacing: Theme.Spacing.s8) {
                                ListRow(label: "What things mean", value: "")
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Theme.Palette.mutedText)
                                    .accessibilityHidden(true)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                    BackupSection(model: model)
                        .padding(.top, Theme.Spacing.s8)

                    #if DEBUG
                    NavigationLink("Band data report", value: TodayRoute.bandDataReport)
                        .buttonStyle(.veselSecondary)
                    #endif

                    Button("Forget this Loop") { model.forget = .confirm }
                        .buttonStyle(.veselDestructive)
                        .padding(.top, Theme.Spacing.s16)

                    Text(
                        """
                        Vesel reads your Loop with the Polar BLE SDK, © Polar Electro Oy, used under Polar's SDK licence. \
                        Polar, Polar Loop and Nightly Recharge are Polar Electro's names; their measurements come from Polar. \
                        Vesel isn't made or endorsed by Polar.

                        Vesel is not a medical device. It doesn't diagnose, treat or prevent anything.

                        Vesel by Solid Vibes. Also uses GRDB.swift © Gwendal Roué (MIT), swift-protobuf © Apple Inc. (Apache 2.0) \
                        and Zip © Roy Marmelstein (MIT).
                        """
                    )
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.Spacing.s16)
                }
                .padding(.horizontal, Theme.Spacing.edge)
                .padding(.top, Theme.Spacing.s16)
                .padding(.bottom, Theme.Spacing.s32)
            }
            TopFade()
        }
        .navigationTitle("Loop & settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .sheet(isPresented: Binding(get: { model.scanningBackupQR }, set: { model.scanningBackupQR = $0 })) {
            BackupScannerView { qr in Task { await model.setUpBackup(qr) } }
        }
        .sheet(isPresented: Binding(get: { model.forget != nil }, set: { if !$0 { model.forget = nil } })) {
            if let step = model.forget {
                ForgetLoopSheet(model: model, step: step)
            }
        }
    }

    private var wristSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
            if model.wristNotSaved {
                ErrorCard(
                    title: "Not saved",
                    message: "Your Loop didn't take the change, so nothing changed on your phone either. Keep the Loop close and try again."
                )
            }
            section("Worn on") {
                Picker(
                    "Worn on",
                    selection: Binding(
                        get: { model.wrist },
                        set: { side in Task { await model.chooseWrist(side) } }
                    )
                ) {
                    Text("Left").tag(WristSide.left)
                    Text("Right").tag(WristSide.right)
                }
                .pickerStyle(.segmented)
                .disabled(model.savingWrist)
                .padding(.vertical, Theme.Spacing.s8)
            }
            Text("Polar's sleep and activity maths are tuned to the wrist you wear it on.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Palette.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var connectionText: String {
        switch model.connection {
        case .connected: "Connected"
        case .connecting: "Connecting…"
        case .disconnected: "Not nearby"
        }
    }

    private var batteryText: String {
        guard let band = model.band, let percent = band.batteryPercent else { return "Not read yet" }
        return band.isBatteryLow ? "\(percent) % · Low" : "\(percent) %"
    }

    private var lastReadText: String {
        model.lastRead.map { "Last read \(Formatters.ago($0, now: environment.clock.now))" } ?? "Not read yet"
    }

    private var backupText: String {
        switch model.backupIsSetUp {
        case true?: model.backup?.lastBackup.map(relative) ?? "Not yet"
        case false?: "Not set up"
        case nil: ""
        }
    }

    private var liveHeartRateText: String {
        guard let live = environment.liveHeartRate.current else { return "Waiting for your Loop…" }
        if live.skinContact == false { return "Not on the wrist" }
        return "\(live.bpm) bpm"
    }

    private func relative(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
            Text(title)
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Palette.mutedText)
            GlassCard {
                VStack(spacing: 0) { content() }
            }
        }
    }
}

#if DEBUG
#Preview("Normal") {
    PreviewHost { environment in
        NavigationStack { LoopSettingsView(environment: environment) }
    }
}
#endif
