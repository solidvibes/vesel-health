import Foundation
import VeselBackupKit

/// Where the app's files are. Debug builds accept `-VeselServerHome <dir>`, `-VeselServerHost <name>` and
/// `-VeselDaemonPlist <path>` so test runs never touch the real data folder; Release ignores them.
struct AppConfig {
    let userHome: URL
    let serverHome: ServerHome
    let daemonPlist: URL
    let launch: ServerLaunch
    /// A Debug run on a scratch folder keeps its settings apart.
    let defaults: UserDefaults

    static let testRunDefaults = "app.vesel.backup.testrun"

    init(userHome: URL, serverHome: ServerHome, daemonPlist: URL, bundledServer: URL, hostOverride: String?, isTestRun: Bool) {
        self.userHome = userHome
        self.serverHome = serverHome
        self.daemonPlist = daemonPlist
        self.launch = ServerLaunch(
            userHome: userHome,
            temporaryDirectory: FileManager.default.temporaryDirectory,
            serverHome: serverHome,
            bundledServer: bundledServer,
            hostOverride: hostOverride
        )
        self.defaults = isTestRun ? UserDefaults(suiteName: Self.testRunDefaults) ?? .standard : .standard
    }

    static func current() -> AppConfig {
        let userHome = URL(filePath: NSHomeDirectory())
        let bundledServer = Bundle.main.resourceURL!.appending(path: "server", directoryHint: .isDirectory)
        var serverHome = ServerHome.standard(userHome: userHome)
        var daemonPlist = DaemonCheck.standardPlist
        var hostOverride: String?
        var isTestRun = false
        #if DEBUG
        if let path = argument("-VeselServerHome") {
            serverHome = ServerHome(root: URL(filePath: path, directoryHint: .isDirectory))
            isTestRun = true
        }
        if let path = argument("-VeselDaemonPlist") {
            daemonPlist = URL(filePath: path)
        }
        hostOverride = argument("-VeselServerHost")
        #endif
        return AppConfig(
            userHome: userHome,
            serverHome: serverHome,
            daemonPlist: daemonPlist,
            bundledServer: bundledServer,
            hostOverride: hostOverride,
            isTestRun: isTestRun
        )
    }

    #if DEBUG
    private static func argument(_ name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
    #endif
}
