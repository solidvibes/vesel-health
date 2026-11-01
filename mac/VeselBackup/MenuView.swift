import AppKit
import SwiftUI
import VeselBackupKit

extension ServerState {
    var icon: String {
        switch self {
        case .on, .starting: "externaldrive.badge.checkmark"
        case .off: "externaldrive"
        case .problem, .terminalSetup: "externaldrive.badge.exclamationmark"
        case .notPaired: "externaldrive.badge.plus"
        }
    }

    func status(host: String) -> String {
        switch self {
        case .on: "On · \(host)"
        case .off: "Off · your iPhone keeps its rows until it's back on"
        case .starting: "Getting ready…"
        case .problem(.uvMissing): "Needs uv to run. Install it with Homebrew: brew install uv"
        case .problem(.portBusy): "Something else is using port 8443, so the backup can't start."
        case .problem(.keepsStopping): "The backup server keeps stopping."
        case .terminalSetup: "The Terminal set-up runs the backup on this Mac."
        case .notPaired: "Not paired yet"
        }
    }
}

enum ReadmeLink {
    static let base = "https://github.com/solidvibes/vesel-health/blob/main/server/README.md"
    static let switchWays = URL(string: "\(base)#switch-a-mac-from-the-terminal-set-up-to-the-app")!
    static let portBusy = URL(string: "\(base)#port-8443-is-busy")!
}

enum PairingStep {
    case none
    case confirming
    case working
    case shown(PairingCode)
    case failed(String)
}

struct MenuView: View {
    @Bindable var controller: ServerController
    let loginItem: LoginItem
    @State private var pairing: PairingStep = .none
    var now: () -> Date = Date.init

    var body: some View {
        Group {
            if case .shown(let code) = pairing {
                PairingView(code: code) { pairing = .none }
            } else {
                menu
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear {
            controller.refreshStats()
            loginItem.refresh()
        }
        .onDisappear { pairing = .none }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            if case .shown = pairing { pairing = .none }
        }
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            problemActions
            if showsServerSwitch {
                SwitchRow(title: "Backup server", isOn: Binding(get: { controller.serverOn }, set: { controller.setServerOn($0) }))
            }
            Divider()
            BackupSummary(stats: controller.stats, now: now())
            Divider()
            pairSection
            loginSection
            Divider()
            Button("Quit Vesel Backup") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .keyboardShortcut("q")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: controller.state.icon)
                .font(.title2)
                .foregroundStyle(isProblem ? Color.red : Color.primary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Vesel Backup")
                    .font(.headline)
                Text(controller.state.status(host: controller.host))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var problemActions: some View {
        switch controller.state {
        case .problem(.uvMissing):
            Button("Copy “brew install uv”") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("brew install uv", forType: .string)
            }
        case .problem(.portBusy):
            Button("How to fix") { NSWorkspace.shared.open(ReadmeLink.portBusy) }
        case .problem(.keepsStopping):
            HStack {
                Button("Try again") { controller.tryAgain() }
                Button("Show log") { NSWorkspace.shared.activateFileViewerSelecting([controller.config.serverHome.log]) }
            }
        case .terminalSetup:
            Button("How to switch") { NSWorkspace.shared.open(ReadmeLink.switchWays) }
        case .notPaired, .off, .starting, .on:
            EmptyView()
        }
    }

    @ViewBuilder
    private var pairSection: some View {
        if controller.state != .terminalSetup {
            switch pairing {
            case .confirming:
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your iPhone stops backing up until it scans the new code.")
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Cancel") { pairing = .none }
                        Button("Make a new code") { makeCode() }
                            .keyboardShortcut(.defaultAction)
                    }
                }
            case .working:
                Text("Making a pairing code…")
                    .foregroundStyle(.secondary)
            case .failed(let reason):
                VStack(alignment: .leading, spacing: 4) {
                    Label("Couldn't make a pairing code", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    if !reason.isEmpty {
                        Text(reason)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Try again") { makeCode() }
                }
            case .none, .shown:
                if controller.isPaired {
                    Button("Pair again…") { pairing = .confirming }
                } else {
                    Button("Pair phone…") { makeCode() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private var loginSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SwitchRow(title: "Open at login", isOn: Binding(get: { loginItem.isOn }, set: { loginItem.set($0) }))
                .disabled(!LoginItem.isAvailable)
            if loginItem.status == .requiresApproval {
                Text("Allow it in System Settings › General › Login Items")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Open Login Items") { loginItem.openSystemSettings() }
            }
        }
    }

    private var showsServerSwitch: Bool {
        controller.state != .notPaired && controller.state != .terminalSetup
    }

    private var isProblem: Bool {
        if case .problem = controller.state { return true }
        return controller.state == .terminalSetup
    }

    private func makeCode() {
        pairing = .working
        Task {
            switch await controller.pair() {
            case .code(let code):
                if case .working = pairing { pairing = .shown(code) }
            case .failed(let reason):
                if case .working = pairing { pairing = .failed(reason) }
            }
        }
    }
}

struct SwitchRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

struct BackupSummary: View {
    let stats: BackupStats
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if stats.isEmpty {
                Text("Nothing backed up yet")
                    .foregroundStyle(.secondary)
            } else {
                if let last = stats.lastReceivedAt {
                    row("Last backup", MenuLabels.lastBackup(last, now: now, calendar: .current))
                        .font(.subheadline.weight(.semibold))
                }
                ForEach(MenuLabels.lines(for: stats.counts)) { line in
                    row(line.label, line.count.formatted())
                        .font(.subheadline)
                }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
    }
}
