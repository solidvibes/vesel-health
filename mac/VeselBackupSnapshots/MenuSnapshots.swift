import AppKit
import SwiftUI
import Testing
import VeselBackupKit

/// Renders the real menu panel offscreen, one PNG per state. Runs only when asked:
/// `TEST_RUNNER_VESEL_SHOTS=<png folder> TEST_RUNNER_VESEL_SHOTS_HOME=<scratch server home> TEST_RUNNER_VESEL_SHOTS_MODE=pair|states xcodebuild test …`
/// `pair` renders "not paired" and pairs that scratch home through the bundled `setup.sh` (a throwaway token, on screen only);
/// `states` renders the rest with that home's backup counts.
@MainActor
struct MenuSnapshots {
    nonisolated static let environment = ProcessInfo.processInfo.environment
    nonisolated static let shots = environment["VESEL_SHOTS"].map { URL(filePath: $0, directoryHint: .isDirectory) }
    nonisolated static let home = environment["VESEL_SHOTS_HOME"].map { URL(filePath: $0, directoryHint: .isDirectory) }
    nonisolated static let mode = environment["VESEL_SHOTS_MODE"]
    nonisolated static let server = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "server", directoryHint: .isDirectory)

    func config(home: URL, daemonPlist: URL = URL(filePath: "/nonexistent/app.vesel.server.plist")) -> AppConfig {
        AppConfig(
            userHome: URL(filePath: NSHomeDirectory()),
            serverHome: ServerHome(root: home),
            daemonPlist: daemonPlist,
            bundledServer: Self.server,
            hostOverride: "localhost",
            isTestRun: true
        )
    }

    @Test(.enabled(if: mode == "pair" && shots != nil && home != nil))
    func notPairedAndPairing() async throws {
        let shots = try #require(Self.shots)
        let home = try #require(Self.home)
        let controller = ServerController(config: config(home: home))
        controller.launch()
        try await Task.sleep(for: .milliseconds(200))
        #expect(controller.state == .notPaired)
        try await render(MenuView(controller: controller, loginItem: LoginItem()), to: shots.appending(path: "1-not-paired.png"))

        let outcome = await controller.pair()
        await controller.stop()
        guard case .code(let code) = outcome else {
            Issue.record("pairing failed")
            return
        }
        #expect(controller.isPaired)
        try await render(PairingView(code: code) {}.padding(16).frame(width: 320), to: shots.appending(path: "2-pairing-qr.png"))
    }

    @Test(.enabled(if: mode == "states" && shots != nil && home != nil))
    func everyOtherState() async throws {
        let shots = try #require(Self.shots)
        let home = try #require(Self.home)
        let states: [(String, ServerState)] = [
            ("3-starting", .starting),
            ("4-on", .on),
            ("5-off", .off),
            ("6-uv-missing", .problem(.uvMissing)),
            ("7-port-busy", .problem(.portBusy)),
            ("8-keeps-stopping", .problem(.keepsStopping)),
        ]
        for (name, state) in states {
            let controller = ServerController(config: config(home: home))
            controller.state = state
            try await render(MenuView(controller: controller, loginItem: LoginItem()), to: shots.appending(path: "\(name).png"))
        }

        let daemon = FileManager.default.temporaryDirectory.appending(path: "app.vesel.server.plist")
        try Data().write(to: daemon)
        defer { try? FileManager.default.removeItem(at: daemon) }
        let controller = ServerController(config: config(home: home, daemonPlist: daemon))
        controller.launch()
        try await Task.sleep(for: .milliseconds(200))
        #expect(controller.state == .terminalSetup)
        try await render(MenuView(controller: controller, loginItem: LoginItem()), to: shots.appending(path: "9-terminal-setup.png"))
    }

    func render(_ view: some View, to url: URL) async throws {
        let root =
            view
            .padding(0)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .light)
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        try await Task.sleep(for: .milliseconds(600))
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        window.setContentSize(size)
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)
    }
}
