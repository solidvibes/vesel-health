import SwiftUI
import VeselSync

/// Loop & settings › Mac backup: set up by scanning the QR, what's waiting, Back up now, Remove backup.
struct BackupSection: View {
    let model: LoopSettingsModel
    @State private var confirmsRemove = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
            Text("Mac backup")
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Palette.mutedText)
            switch model.backupIsSetUp {
            case true?: setUp
            case false?: notSetUp
            case nil: EmptyView()
            }
        }
        .confirmationDialog("Remove backup?", isPresented: $confirmsRemove, titleVisibility: .visible) {
            Button("Remove backup", role: .destructive) { Task { await model.removeBackup() } }
        } message: {
            Text("This iPhone stops sending copies to your Mac. The copy already there stays.")
        }
    }

    @ViewBuilder private var notSetUp: some View {
        GlassCard {
            Text("Keeps a copy of everything on your Mac at home, over your home Wi-Fi only. Nothing goes to anyone's cloud.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.mutedText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        if let error = model.backupSetUpError {
            ErrorCard(title: "Couldn't set up backup", message: Self.message(error))
        }
        Button {
            model.scanningBackupQR = true
        } label: {
            if model.settingUpBackup { ProgressView() } else { Text("Set up backup") }
        }
        .buttonStyle(.veselSecondary)
        .disabled(model.settingUpBackup)
    }

    @ViewBuilder private var setUp: some View {
        GlassCard {
            VStack(spacing: 0) {
                ListRow(label: "Waiting to back up", value: model.backupWaiting == 0 ? "Nothing" : model.backupWaiting.formatted())
                if let note = Self.note(model.backup?.lastOutcome) {
                    Divider()
                    Text(note)
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Palette.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: Theme.Size.row, alignment: .leading)
                }
            }
        }
        if let outcome = model.backup?.lastOutcome, outcome.needsNewQR {
            ErrorCard(
                title: "Scan the QR again",
                message: outcome == .unauthorized
                    ? "Your Mac no longer accepts this iPhone's key. Make a new code on your Mac (Pair again in Vesel Backup, or setup.sh --force) and scan it."
                    : "Something answered that isn't your Mac, or its certificate changed. Nothing was sent. Scan the QR from your Mac again.",
                actionTitle: "Scan QR again",
                action: { model.scanningBackupQR = true }
            )
        } else if let error = model.backupSetUpError {
            ErrorCard(title: "Couldn't set up backup", message: Self.message(error))
        }
        Button {
            Task { await model.backUpNow() }
        } label: {
            if model.backingUp || model.settingUpBackup { ProgressView() } else { Text("Back up now") }
        }
        .buttonStyle(.veselSecondary)
        .disabled(model.backingUp || model.settingUpBackup)
        Button("Remove backup") { confirmsRemove = true }
            .buttonStyle(.veselSecondary)
    }

    private static func note(_ outcome: BackupOutcome?) -> String? {
        switch outcome {
        case .away?: "Your Mac didn't answer last time. Vesel backs up after a sync on your home Wi-Fi."
        case .failed?: "The last backup didn't finish. What's left goes after the next sync."
        case .otherFormat?: "Your Mac runs another version of the backup server. Update it on your Mac."
        case .backedUp?, .unauthorized?, .wrongCertificate?, nil: nil
        }
    }

    static func message(_ error: Backup.SetUpError) -> String {
        switch error {
        case .notABackupQR:
            "That isn't a Vesel backup QR. Scan the code Vesel Backup or setup.sh shows on your Mac."
        case .unreachable(.away):
            "Your Mac didn't answer. Be on your home Wi-Fi with your Mac on, then scan again."
        case .unreachable(.wrongCertificate):
            "Something answered that isn't your Mac. Nothing was sent. Scan again on your home Wi-Fi."
        case .unreachable(.unauthorized):
            "Your Mac didn't accept the key in this QR. Make a new code on your Mac (Pair again in Vesel Backup, or setup.sh --force) and scan it."
        case .unreachable(.otherFormat):
            "Your Mac runs another version of the backup server. Update it on your Mac."
        case .unreachable:
            "Your Mac answered but couldn't be set up. Try again."
        case .keychain:
            "This iPhone couldn't keep the backup key. Try again."
        }
    }
}
